(*
 Owned and copyright BitBlaze, 2007. All rights reserved.
 Do not copy, disclose, or distribute without explicit written
 permission.
*)
(**
   A driver to operate on execution traces generated by TEMU. 
   
   @author Zhenkai Liang, Juan Caballero
*)
open Vine_util 
module Trace = Temu_trace

type cmdlineargs_t = {
    mutable trace_filename : string; 
    mutable fmap_filename : string;
    mutable calls_filename : string;
    mutable modlist_filename : string;
    mutable funlist_filename : string;
    mutable first : int64; 
    mutable last : int64;
    mutable count : bool;  
    mutable output : string; 
    mutable taintpair : (int32*int32);
    mutable tainted_only : bool;
    mutable print_header : bool;
    mutable verbose : bool;
    mutable reduced_flog : bool;
    mutable tid : int32;
    mutable function_stack_start_size : int;
    mutable createindex : bool; 
    mutable eiptrace : bool;
    mutable extra_modules_l : (int64*int64*string) list;
  };;
    
let parsecmdline = 
  let cmdlineargs = {
      trace_filename = "";
      fmap_filename = "";
      calls_filename = "";
      modlist_filename = "";
      funlist_filename = "";
      first = 1L;
      last = 0L;
      count = false; 
      output = "";
      taintpair = (Int32.minus_one,Int32.minus_one);
      tainted_only = false;
      print_header = false;
      verbose = false;
      reduced_flog = false;
      tid = 0l;
      function_stack_start_size = 100;
      createindex = false; 
      eiptrace = false;
      extra_modules_l = [];
    }
  in
  let set_taintoffset s = 
    let (origin,_) = cmdlineargs.taintpair in
    let offset = Int32.of_string s in
    cmdlineargs.taintpair <- (origin,offset)
  in
  let set_taintorigin s = 
    let (_,offset) = cmdlineargs.taintpair in
    let origin = Int64.to_int32 (Int64.of_string s) in 
    cmdlineargs.taintpair <- (origin,offset)
  in
  let add_module s = 
    let tl = Str.split (Str.regexp ":") s in
    try (
      let start_addr = Int64.of_string (List.hd tl) in
      let size = Int64.of_string (List.nth tl 1) in
      let name = List.nth tl 2 in
      cmdlineargs.extra_modules_l <- 
	(start_addr,size,name) :: cmdlineargs.extra_modules_l
    )
    with _ -> (
      Printf.fprintf stderr "Invalid module info: %s\n%!" s;
      exit 1
    )
  in
  let arg_spec = [
      ("-first", 
      Arg.String (fun s -> cmdlineargs.first <- Int64.of_string s),
      "<int> Line number of first instruction"); 

      ("-last", 
      Arg.String (fun s -> cmdlineargs.last <- Int64.of_string s),
      "<int> Line number of last instruction"); 

      ("-count", 
      Arg.Unit (fun s -> cmdlineargs.count <- true),
      "<> Display line number"); 
      
      ("-o",
      Arg.String (fun s -> cmdlineargs.output <- s),
      "<string> Output file name");

      ("-trace", 
      Arg.String (fun s -> cmdlineargs.trace_filename <- s),
      "<string> Name of input trace file"); 

      ("-taintedonly", 
      Arg.Unit (fun s -> cmdlineargs.tainted_only <-true),
      "<> Process only tainted instructions"); 
      
      ("-taintpair", 
      Arg.Tuple ([Arg.String set_taintorigin; Arg.String set_taintoffset]),
      "<int32> <int32> Process only tainted instructions operating on this " ^ 
	"origin (int32) + offset (int) pair");

      ("-header",
      Arg.Unit (fun s -> cmdlineargs.print_header <- true),
      "<> Print trace header information before instruction sequence"); 

      ("-fmap",
      Arg.String (fun s -> cmdlineargs.fmap_filename <- s),
      "<string> Name of input function map. Used to print function names " ^ 
	"at call/ret instructions");

      ("-flog",
      Arg.String (fun s -> cmdlineargs.calls_filename <- s),
      "<string> Name of output file to receive summary of call/ret in trace." ^ 
	" Requires -fmap option");  

      ("-flogr",
      Arg.String (fun s -> cmdlineargs.calls_filename <- s; 
	cmdlineargs.reduced_flog <- true),
      "<string> Same as -fmap but prints only calls from main module");  

      ("-modlist",
      Arg.String (fun s -> cmdlineargs.modlist_filename <- s),
      "<string> Print list of modules seen in trace to given file");  

      ("-funlist",
      Arg.String (fun s -> cmdlineargs.funlist_filename <- s),
      "<string> Print list of known functions seen in trace to given file");  

      ("-tid",
      Arg.Int (fun i -> cmdlineargs.tid <- Int32.of_int i),
      "<int> Process only instructions with this thread identifier");  

      ("-v",
      Arg.Unit (fun () -> cmdlineargs.verbose <- true),
      "<> Verbose. Prints more info per instruction");

      ("-funstacksize",
      Arg.Int (fun x -> cmdlineargs.function_stack_start_size <- x),
      "<int> Set function stack start size to this value");

      ("-createindex",
      Arg.Unit (fun s -> cmdlineargs.createindex <- true),
      "<> Create an index file for the trace. Outputs trace.idx file"); 

      ("-eip",
      Arg.Unit (fun s -> cmdlineargs.eiptrace <- true),
      "<> Print only EIP of instruction");

      ("-emod",
      Arg.String add_module,
      ("<adddr>:<size>:<name> Add a module to the module list " ^
        "using given base address, module size and module name"));

    ] 
  in 
  let () =
    Arg.parse arg_spec (fun s -> ()) 
      "Usage: trace_reader [options] -trace <trace_file>"
  in
    cmdlineargs

(************* START of TRACE CALLS CODE ********************)
(* Globals *)
let first_level_call = ref false

(* Function information per thread *)
type thread_funinfo_t = {
  thread_id : int32;
  mutable thread_found_call : bool;
  mutable thread_found_ret : bool;
  mutable thread_next_inst : Libasmir.address_t;
  thread_fun_stack : (string*string*Libasmir.address_t) Stack.t;
}

(* Initialize thread information *)
let init_thread_info tid stack_size = 
  let st = 
    (Stack.create () : ((string*string*Libasmir.address_t) Stack.t))
  in 
  let _ =
    for i = 0 to stack_size do
      Stack.push ("unseen","unseen",0L) st;
    done
  in
  {
    thread_id = tid;
    thread_found_call = false;
    thread_found_ret = false;
    thread_next_inst = 0L;
    thread_fun_stack = st;
  }

(* Read function map from file *)
let read_function_map filename =
  let function_map = Hashtbl.create 10 in
  let ic =
    try open_in filename
    with Not_found -> failwith "Netlog file not found"
  in
  let ic = IO.input_channel ic in 
  let rec read_all_lines () =
    let line = IO.read_line ic in
    (* process line *)
    let re = Str.regexp "[ \t]+" in
    let param_list = Str.split re line in
    let eip = Int64.of_string (List.nth param_list 0) in
    let mod_name = (List.nth param_list 1) in
    let fun_name = (List.nth param_list 2) in
    let offset = int_of_string (List.nth param_list 3) in
    Hashtbl.replace function_map eip (mod_name,fun_name,offset);
    read_all_lines ()
  in
  let _ = 
    try
      read_all_lines ()
    with
      IO.No_more_input -> IO.close_in ic
  in function_map

(* Print function map *)
let print_function_map function_map =
  let keys = get_hash_keys function_map in
  let keys = List.sort Pervasives.compare keys in
  let process_eip last_eip curr_eip =
    if (last_eip <> curr_eip) then
      (
        let (mod_name,fun_name,offset) =
          try Hashtbl.find function_map curr_eip
          with Not_found -> ("","",-1)
        in
        let _ = match offset with
          (-1) -> ()
          | _ ->
            Printf.printf "%s::%s @ 0x%08Lx (0x%04x)\n"
              mod_name fun_name curr_eip offset
        in
        curr_eip
      )
      else last_eip
  in
  let _ = List.fold_left process_eip 0L keys
  in ()

(* Read module base addresses from the header of the trace *)
let read_module_addresses ti =
  let module_base_map = Hashtbl.create 10 in
  let procs = ti#processes in 
  let num_procs = List.length procs in
  let _ =
    if (num_procs > 1)
    then failwith "More than one process in trace. Exiting...";
  in
  let proc = 
    try List.hd procs 
    with _ -> failwith "No processes in trace. Exiting..." 
  in
  (* Printf.printf "Process: %s PID: %d\n%!" proc#name proc#pid; *)
  let add_module curr_mod =
    (*  Printf.printf "\t Module: %s @ 0x%08Lx Size: %Ld\n%!" 
        curr_mod#name curr_mod#base curr_mod#size; *)
    Hashtbl.add module_base_map
      curr_mod#name (curr_mod#base,curr_mod#size)
  in
    (* map module info in the reverse order so that it comes in the right
       order when calling with Hashtbl.fold *)
  let _ = List.iter add_module (List.rev proc#modules) in
  module_base_map


(* Is call instruction? *)
let is_call_insn insn =
  let opcode = int_of_char insn#rawbytes.(0) in
  let intrm = (((int_of_char insn#rawbytes.(1)) lsr 3) land 7) in
  match (opcode,intrm) with
    | (0xe8, _) | (0xff, 2) | (0x9a, _) | (0xff, 3) -> true
    | _ -> false

(* Is return instruction? *)
let is_ret_insn insn =
  let opcode = int_of_char insn#rawbytes.(0) in
  let intrm = (((int_of_char insn#rawbytes.(1)) lsr 3) land 7) in
  match (opcode,intrm) with
    | (0xc3, _) | (0xcb, _) | (0xc2, _) | (0xca, _) -> true
    (* Special handling for 'repz ret' *)
    | (0xf3, _) when (int_of_char insn#rawbytes.(1) = 0xc3) -> true
    | _ -> false

(* Is indirect jump? *)
let is_ijmp_insn insn =
  let opcode = int_of_char insn#rawbytes.(0) in
  let intrm = (((int_of_char insn#rawbytes.(1)) lsr 3) land 7) in
  match (opcode,intrm) with
    | (0xff, 4) -> true
    | _ -> false

(* Return the module information for the given EIP *)
let find_module module_base_map addr =
  let check_module modname (base,size) in_module =
    if (in_module <> "unknown")
    then in_module
    else
      if ((addr >= base) && (addr <= (Int64.add base size))) then modname
      else "unknown"
  in
  Hashtbl.fold check_module module_base_map "unknown"

(* Add function to function map *)
let add_fun_to_funmap map mod_name fun_name insn_ctr = 
  Hashtbl.add map (mod_name,fun_name) insn_ctr

(* Check if corresponding call is in stack *)
let check_for_call function_stack address = 
  let flag = ref false in
  let process_call (mod_name,fun_name,next_inst) = 
    if (next_inst = address) then flag := true
  in
  Stack.iter process_call function_stack;
  !flag 

(* Print the call/return information for an instruction *)
let process_insn_calls function_stack_map function_map module_base_map 
  fun_seen_map count oc reduced procname stack_size inst = 
  match (function_stack_map,function_map,module_base_map,fun_seen_map) with 
    Some(function_stack_map),Some(function_map), Some(module_base_map),
    Some(fun_seen_map) -> 

    (* Get the function info for this thread *)
    let tinfo = 
      try Hashtbl.find function_stack_map inst#thread_id
      with Not_found -> 
        let info = init_thread_info inst#thread_id stack_size in
        Hashtbl.add function_stack_map inst#thread_id info;
        info
    in
    let function_stack = tinfo.thread_fun_stack in

    (* If previous instruction was call, check module/function names *)
    if (tinfo.thread_found_call) && (not (is_ijmp_insn inst)) then (
      (* Check if it is a known function *)
      let (mod_name,fun_name) =
	try (
	  let (mod_name,fun_name,_) =
	    Hashtbl.find function_map inst#address in
	  (mod_name,fun_name)
	)
	with Not_found -> (
	  let mod_name = find_module module_base_map inst#address in
          let eip_str = Printf.sprintf "%Lx" inst#address in
          let fun_name = Printf.sprintf "sub_%s" (String.uppercase eip_str) in
	  (mod_name,fun_name)
	)
      in
      Stack.push (mod_name,fun_name,tinfo.thread_next_inst) function_stack;
      Printf.printf "\t%s::%s (%d)%!"
	mod_name fun_name (Stack.length function_stack); 
      (* add_fun_to_funmap fun_seen_map mod_name fun_name count; *)
      let _ = 
	match oc with 
	  Some(call_oc) -> 
	    if ((not reduced) || (reduced && !first_level_call)) then 
		Printf.fprintf call_oc "%06Ld %ld CALL %s::%s (%d)\n"
		  count inst#thread_id mod_name fun_name 
		  (Stack.length function_stack); 
	  | None -> () 
      in
      tinfo.thread_found_call <- false;
      first_level_call := false;
    );
    if (tinfo.thread_found_ret) then (
      let curr_len = Stack.length function_stack in
      let (mod_name,fun_name,next_inst) =
	try Stack.pop function_stack
	with Stack.Empty ->
	  Printf.printf "Current depth index: %d\n%!" curr_len;
	  failwith "Try increasing function_stack_start_size?"
      in
      (* It turns out that at least in Linux ret instructions are sometimes 
          called without a corresponding call, specially in the context 
          of system calls.
          Thus need to handle spurious ret instructions *)

      (* Check if this instruction is the one we were expecting, 
          i.e., the one that follows the call *)
      let (mod_name,fun_name,curr_len) = 
        if ((fun_name = "unseen") || (inst#address = next_inst))
	  then (mod_name,fun_name,curr_len)
	  else (
            (* Check if we are missing some calls, by scanning the stack 
                 for the corresponding call *)
            let in_stack = check_for_call function_stack inst#address in
            (* If there is a corresponding call in the stack, 
                that should mean we missed some rets, pop the stack till 
                the corresponding call, inclusive *)
            if (in_stack) then (
              let rec pop_stack ctr = 
                let (mn,fn,ni) = Stack.pop function_stack in
                if (ni = inst#address) then (
                  let cl = Stack.length function_stack in
		  (mn,fn,cl+1)
		)
		else pop_stack (ctr+1)
              in
              pop_stack 0
	    )
	    else (
	      (* Otherwise, it is an spurious ret, keep old info *)
	      Stack.push (mod_name,fun_name,next_inst) function_stack; 
	      ("spurious","spurious",0)
	    )
	  )
      in
      Printf.printf "\t%s::%s (%d)%!" mod_name fun_name curr_len;
      (match oc with 
	Some(call_oc) -> (
	  if (not reduced) then (
	    Printf.fprintf call_oc "%06Ld %ld RET %s::%s (%d)\n" 
	      count inst#thread_id mod_name fun_name curr_len;
	  )
	  else if (fun_name = "spurious") then (
	    let (src_modname,_,_) = Stack.top function_stack in
	    if (src_modname = procname) then (
	      try (
		let (mod_name,fun_name,_) =
		  Hashtbl.find function_map inst#address 
		in
		Printf.fprintf call_oc "%06Ld %ld SPURIOUS_RET %s::%s\n"
		  count inst#thread_id mod_name fun_name
	      )
	      with Not_found -> (
		let eip_str = Printf.sprintf "%Lx" inst#address in
		let mod_name = find_module module_base_map inst#address in
		let fun_name = 
		  Printf.sprintf "sub_%s" (String.uppercase eip_str) 
		in
                Printf.fprintf call_oc "%06Ld %ld SPURIOUS_RET %s::%s\n"
                  count inst#thread_id mod_name fun_name
	      )
	    )
	  )
	)
	| None -> () 
      );
      tinfo.thread_next_inst <- 0L;
      tinfo.thread_found_ret <- false
    );
    if (is_call_insn inst) then (
      let modname = find_module module_base_map inst#address in
      if (modname = procname) then (first_level_call := true);
      tinfo.thread_next_inst <- 
	Int64.add inst#address (Int64.of_int inst#inst_size);
      tinfo.thread_found_call <- true
    )
    else if (is_ret_insn inst) then (
      tinfo.thread_found_ret <- true
    )
    (* Special case for calls without ret. Flag if this case is found *)
    else if (inst#address = tinfo.thread_next_inst) then (
      Printf.fprintf stderr "Found call without ret at 0x%Lx\n%!"
        inst#address; 
    )
    else ()
  | _ -> ()

(************* END of TRACE CALLS CODE **********************)

let opaddr_str op = 
  let default_str = Printf.sprintf "0x%08Lx" op#opaddr in
  match op#optype with 
    | Trace.TRegister -> (
	match op#opaddr with
	  (* segment registers *)
	  | 100L -> "es"
	  | 101L -> "cs"
	  | 102L-> "ss"
	  | 103L -> "ds"
	  | 104L -> "fs"
	  | 105L -> "gs"
	  (*address-modifier dependent registers *)
	  | 108L -> default_str
	  | 109L -> default_str
	  | 110L -> default_str
	  | 111L -> default_str
	  | 112L -> default_str
	  | 113L -> default_str
	  | 114L -> default_str
	  | 115L -> default_str
	  (* 8-bit registers *)
	  | 116L -> "al"
	  | 117L -> "cl"
	  | 118L -> "dl"
	  | 119L -> "bl"
	  | 120L -> "ah"
	  | 121L -> "ch"
	  | 122L -> "dh"
	  | 123L -> "bh"
	  (* 16-bit registers *)
	  | 124L -> "ax"
	  | 125L -> "cx"
	  | 126L -> "dx"
	  | 127L -> "bx"
	  | 128L -> "sp"
	  | 129L -> "bp"
	  | 130L -> "si"
	  | 131L -> "di"
	  (* 32-bit registers *)
	  | 132L -> "eax"
	  | 133L -> "ecx"
	  | 134L -> "edx"
	  | 135L -> "ebx"
	  | 136L -> "esp"
	  | 137L -> "ebp"
	  | 138L -> "esi"
	  | 139L -> "edi"
	  (* ??? *)
	  | 150L 
          | _ -> default_str
      )
    | _ -> default_str


let optype_str = function
    | Trace.TRegister -> "R"
    | Trace.TMemLoc -> "M"
    | Trace.TImmediate -> "I"
    | Trace.TJump -> "J"
    | Trace.TFloatRegister -> "F"
    | Trace.TMemAddress -> "A"
    | _ -> ""

let opaccess_str = function
  | Trace.A_RW -> "(RW)"
  | Trace.A_R -> "(R)"
  | Trace.A_W -> "(W)"
  | Trace.A_RCW -> "(RCW)"
  | Trace.A_CW -> "(CW)"
  | Trace.A_CRW -> "(CRW)"
  | Trace.A_CR -> "(CR)"
  | _ -> ""
  
(* Priority functions used when sortening operand list *)
let opaccess_priority = function
  | Trace.A_RCW -> 0
  | Trace.A_R -> 1
  | Trace.A_CR -> 2
  | Trace.A_CRW -> 3
  | Trace.A_RW -> 4
  | Trace.A_W -> 5
  | Trace.A_CW -> 6
  | _ -> 7

let optype_priority = function
  | Trace.TImmediate -> 0
  | Trace.TJump -> 1
  | Trace.TRegister -> 2
  | Trace.TFloatRegister -> 3
  | Trace.TMemAddress -> 4
  | Trace.TMemLoc -> 5
  | Trace.TNone -> 6


(* Operand comparison, used to order operands similarly to older traces *)
let operand_compare op1 op2 =
  let p1 = opaccess_priority op1#opaccess in
  let p2 = opaccess_priority op2#opaccess in
  let cmp1 = Pervasives.compare p1 p2 in
  if (cmp1 <> 0) then cmp1
  else (
    let pt1 = optype_priority op1#optype in 
    let pt2 = optype_priority op2#optype in 
    Pervasives.compare pt1 pt2
  )


(* Store module that instruction belongs to into mod_seen_map *)
let process_insn_module mod_base_map_opt mod_seen_map_opt inst = 
  match (mod_base_map_opt,mod_seen_map_opt) with 
    | (Some(mod_base_map),Some(mod_seen_map)) -> 
      let modname = find_module mod_base_map inst#address in
      Hashtbl.replace mod_seen_map modname true
    | _ -> ()

(* Print map with modules seen in trace *)
let print_mod_seen_map filename map_opt =
  match map_opt with 
    | Some(map) -> 
      let mod_oc = open_out filename in
      let process_mod modname _ l = 
	if (modname <> "unknown") 
	  then modname :: l
	  else l
      in
      let mod_seen_l = Hashtbl.fold process_mod map [] in 
      let sorted_mod_seen_l = List.sort (Pervasives.compare) mod_seen_l in
      List.iter (fun s -> Printf.fprintf mod_oc "%s\n" s) sorted_mod_seen_l;
      close_out mod_oc
    | None -> ()

(* Print function seen map *)
let print_funseen_map filename map_opt = 
  match map_opt with
    | Some(map) ->
      let oc = open_out filename in
      let keys = get_hash_keys map in
      let keys = List.sort (Pervasives.compare) keys in
      let print_pair prev_pair curr_pair = 
	if (curr_pair <> prev_pair) then (
	  let (mod_name,fun_name) = curr_pair in
	  Printf.fprintf oc "%s::%s\n" mod_name fun_name
	);
	curr_pair
      in
      let _ = List.fold_left print_pair ("","") keys in
      close_out oc
    | None -> ()

(* Given an operand, return a string containing the operands info, 
read to print *)
let format_operand_basic opr =
  let format_base_operand opr_b = 
    Printf.sprintf "\t%s@%s[0x%08lx][%d]%s" (optype_str opr_b#optype)
      (opaddr_str opr_b) (opr_b#opvalue) opr_b#oplen (opaccess_str opr_b#opaccess)
  in
  let format_taint_info opr_t = 
    let taint_source i = 
      if (Int64.logand opr_t#taintflag (Int64.of_int (1 lsl i))) <> 0L then
	Printf.sprintf "(%lu, %lu) " opr_t#origin.(i) opr_t#offset.(i)
      else
	"()"
    in
      match opr_t#taintflag with
	  0L -> "\tT0"
	| _ -> (Printf.sprintf "\tT1 {%Lu " opr_t#taintflag)
	    ^(taint_source 0) ^ (taint_source 1) ^
	      (taint_source 2) ^ (taint_source 3) ^ "}"
  in
  match (opr#optype) with
      Trace.TRegister
    | Trace.TMemLoc
    | Trace.TImmediate
    | Trace.TJump
    | Trace.TFloatRegister
    | Trace.TMemAddress ->
	(format_base_operand opr) ^ (format_taint_info opr)
    | Trace.TNone -> ""

(* Same as format_operand_basic, but selects operand given inst and index *)
let format_operand inst index = 
  try (
    let opr = inst#operand.(index) in
    format_operand_basic opr
  )
  with _ -> ""
	  

(* Print trace header *)
let print_header ti = 
  Printf.printf "Trace version: %d\n%!" ti#version;
  Printf.printf "Number of instructions: %Ld\n%!" ti#num_instructions;
  let procs = ti#processes in
    let print_process proc = 
      Printf.printf "Process: %s PID: %d\n%!" proc#name proc#pid;
      let print_module curr_mod =
	Printf.printf "\t Module: %s @ 0x%08Lx Size: %Ld\n%!"
	  curr_mod#name curr_mod#base curr_mod#size
      in
	List.iter print_module proc#modules
    in
    List.iter print_process procs

(* Print an instruction *) 
let print_inst args inst count = 
  let _ = if ((Int64.sub count args.first) > 0L) then print_newline () in
  (* Print instruction counter *)
  let () = if args.count 
      then (Printf.printf "(%08Ld)%!" count)
      else ()
  in
  (* Print address *)
  let _ = Printf.printf "%Lx:\t%!" inst#address in
  (* Print disassembly *)
  let _ = Asmir.print_i386_rawbytes inst#address inst#rawbytes in
  (* Get list of operands in instruction *)
  let op_l = List.rev (Array.to_list inst#operand) in
  (* Order list of operands using special comparison function on access *)
  let op_l = List.sort operand_compare op_l in
  (* Print list of operands *)
  let print_op op = 
    let argstr = format_operand_basic op in
    Printf.printf "%s%!" argstr;
  in
  let _ = List.iter print_op op_l in

  (* If verbose, print additional information *)
  if (args.verbose) then (
    Printf.printf " ESP: %s " (format_operand_basic inst#esp);
    Printf.printf "NUM_OP: %d " inst#num_operands;
    Printf.printf "TID: %ld " inst#thread_id;
    Printf.printf "TP: %s " (Trace.taintprop_str inst#tp);
    Printf.printf "EFLAGS: 0x%08lX " inst#eflags;
    Printf.printf "CC_OP: 0x%08lX " inst#cc_op;
    Printf.printf "DF: 0x%08lX " inst#df;
    (* Get instruction size *)
    let num_raw_bytes = 
      let is = inst#inst_size in
      if (is > 0) then is else 15
    in
    (* Print rawbytes *)
    Printf.printf "RAW: 0x";
    for i = 0 to num_raw_bytes - 1 do
      Printf.printf "%02x" (Char.code(inst#rawbytes.(i))) 
    done;
    (* Print memory addressing registers if any *)
    Printf.printf " MEMREGS: ";
    let num_ops = Array.length inst#operand in
    for i = 0 to (num_ops - 1) do
      try (
	let tmp_op = inst#operand.(i) in
	match tmp_op#optype with 
	| Trace.TMemLoc
	| Trace.TMemAddress -> 
	  let memreg_fmt = 
	    ((format_operand_basic inst#memregs.(i).(0)) ^ 
	      (format_operand_basic inst#memregs.(i).(1)) ^ 
	      (format_operand_basic inst#memregs.(i).(2)))
	  in
	  Printf.printf "%s " memreg_fmt;
	| _ -> ()
      )
      with _ -> ()
    done;
  );
  flush stdout 

(* Write instruction to output stream *)
let output_inst inst someoc =
    match someoc with
	Some(oc) -> inst#serialize oc
      | None -> ()

(* Check if instruction is tainted *)
let is_insn_tainted insn = 
  (* Memory operands *)
  let memreg_operands = 
    let ls_arr = Array.to_list insn#memregs in
    let arr = Array.concat ls_arr in
    Array.to_list arr
  in
  (* Add ESP operand *)
  let memreg_operands = insn#esp :: memreg_operands in

  (* Data operands *)      
  let data_operands = Array.to_list insn#operand in

  (* Check if any operand is tainted *)
  let all_operands = List.rev_append data_operands memreg_operands in
  List.fold_left  (fun t ov -> t || (ov#taintflag <> 0L))
    false all_operands


(* Check if instruction needs to be handled *)
let check_cond args count (inst : Temu_trace.instruction) =
  let checktaint inst (origin,offset) = 
    let op_l = (Array.to_list inst#operand) in
    let operand_uses_taintpair op = 
      let origin_l = Array.to_list op#origin in
      let offset_l = Array.to_list op#offset in
      let check_pair flag byte_origin byte_offset = 
        ((byte_origin = origin) && (byte_offset = offset)) || flag
      in
      List.fold_left2 check_pair false origin_l offset_l
    in
    List.exists operand_uses_taintpair op_l
  in
  if ((args.last = 0L || count <= args.last) &&
    (count >= args.first) &&
    (count >= args.first) &&
    (args.taintpair = (Int32.minus_one,Int32.minus_one) || 
      checktaint inst args.taintpair) && 
    (args.tainted_only = false || (is_insn_tainted inst)) &&
    (args.tid = 0l || (args.tid = inst#thread_id))) &&
    (not args.createindex)
  then
    true
  else 
    false
;;



(* Parse the command line *)
let args = parsecmdline in

(* Open the trace *)
let tracename = 
  if (args.trace_filename <> "")
  then
    args.trace_filename
  else
    raise (Arg.Bad "No trace file specified")
in
let trace_iface = Trace.open_trace tracename in

(* Get process name *)
let proc_name = 
  try (List.hd trace_iface#processes)#name 
  with _ -> "unknown"
in

(* Print header if needed *)
if (args.print_header) then print_header trace_iface;

(* Initialize information for printing Windows external calls if needed *)
let (function_stack_map, function_map, module_map,call_log_oc,fun_seen_map) = 
  if (args.fmap_filename <> "") then (
    (* Load function map *)
    let fun_map = read_function_map args.fmap_filename in
    (* Load modules *)
    let mod_map = read_module_addresses trace_iface in
    (* Initialize function stack *)
    let fun_stack_map = Hashtbl.create 10 in
    (* Initialize function log ouput stream if needed *)
    let call_log_oc = 
      if (args.calls_filename <> "") 
      then 
	let call_out = open_out args.calls_filename in
	Some(call_out) 
      else 
	None
    in
    (* Initialize function seen map if needed *)
    let fun_seen_map = Hashtbl.create 40 in
    Some(fun_stack_map),Some(fun_map),Some(mod_map),call_log_oc,
      Some(fun_seen_map)
  )
  else None,None,None,None,None
in

(* Add extra modules to module map *)
let _ = 
  match module_map with 
    | Some (map) -> (
	let add_module (base,size,name) = 
	  Hashtbl.add map name (base,size)
	in
	List.iter add_module args.extra_modules_l;
      )
    | None -> ()
in

(* Initialize module/function list file if needed *)
let (module_seen_map,module_map) = 
  let mod_seen_map = 
    if (args.modlist_filename <> "") then Some(Hashtbl.create 20)
    else None 
  in
  let mod_map = 
    if (args.fmap_filename <> "") then module_map
    else if (args.modlist_filename <> "") then 
      Some(read_module_addresses trace_iface)
    else None
  in
  (mod_seen_map,mod_map)
in

(* Initialize instruction output stream if needed *) 
let someoc = if (args.output <> "") 
  then
    let out = open_out args.output in
    let out = IO.output_channel out in 
    trace_iface#write_header out;
    Some(out)
  else
    None
in 
(* Loop trough all instructions in trace *)
let outchannel =
  let rawchannel =
    if args.createindex then
      open_out_bin (tracename^".idx")
    else
      stdout
  in
    IO.output_channel rawchannel
in
let rec handle_inst trace2 =
  let current_offset = trace2#current_offset () in
  let inst_o =
    try
      Some(trace2#read_instruction)
    with
      IO.No_more_input -> None
  in match inst_o with
      None -> ()
    | Some(inst) ->
	if args.createindex then
	  IO.write_i64 outchannel current_offset;
        if (check_cond args trace2#insn_counter inst)
        then (
	    (* Get function call information if requested *)
	    if (args.fmap_filename <> "") then ( 
	      process_insn_calls function_stack_map function_map module_map 
		fun_seen_map trace2#insn_counter call_log_oc 
		args.reduced_flog proc_name args.function_stack_start_size inst
	    );
	    (* Get module information if requested *)
	    if (args.modlist_filename <> "") 
	      then process_insn_module module_map module_seen_map inst;

	    (* Default processing of instruction. Print instruction info *)
	    let _ = 
	      if (args.eiptrace) then Printf.printf "%08Lx\n" inst#address
	      else print_inst args inst trace2#insn_counter
	    in
	    (* Write instruction to file if requested *)
            output_inst inst someoc;
          );
	if ((args.last <> 0L) && (trace2#insn_counter > args.last)) 
	then () 
	else handle_inst trace2
in
let _ = if args.first > 1L then
  try 
    trace_iface#seek_instruction args.first
  with 
    Trace.No_index -> 
      Printf.fprintf stderr 
        ("No index provided. Scanning sequentially for first instruction.\n" ^^ 
        "You might want to consider creating an index with -createindex.\n%!")
in
let _ = handle_inst trace_iface in
(* Post_processing *)
let _ = 
  if (args.modlist_filename <> "") then (
    print_mod_seen_map args.modlist_filename module_seen_map
  );
  if (args.funlist_filename <> "") then (
    print_funseen_map args.funlist_filename fun_seen_map
  );
  if (args.createindex) then (
    ignore(IO.close_out outchannel)
  )
in
let clean_exit = 
  (match call_log_oc with
    None -> ()
    | Some(oc) -> close_out oc
  );
  (match someoc with
    None -> ()
    | Some(oc) -> IO.close_out oc
  );
  print_newline (); 
    Trace.close_trace trace_iface; 
in
clean_exit
