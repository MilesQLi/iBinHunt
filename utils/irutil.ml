(*
 Owned and copyright BitBlaze, 2007. All rights reserved.
 Do not copy, disclose, or distribute without explicit written
 permission.
*)
(* 
Author: David Brumley
$Id: parseir.ml 855 2007-03-13 17:44:16Z aij $
*)

let usage = "irutil [options]* file\n" in 
let infile = ref "" in 
let infile_set = ref false in
let flag_descope = ref false in 
let flag_alpha = ref false in
let flag_evaluate = ref false in  
let arg_name s = infile := s; infile_set := true in
let main argc argv = 
  (
      let speclist = Vine_parser.defspecs in 
      let speclist = [
		       ("-alphavary", Arg.Set(flag_alpha), 
			"Alpha-vary program");
		       ("-descope", Arg.Set(flag_descope),
			"De-scope program") ;
		       ("-evaluate", Arg.Set(flag_evaluate),
			"Evaluate program in soft");
      ] @ speclist in
	Arg.parse speclist arg_name usage;
	(* FIXME: This silently ignores additional input files. --aij *)
	if(!infile_set = false) then  (
	  Arg.usage speclist usage; exit(-1)
	);
	let prog = (
	  let p = Vine_parser.parse_file !infile in 
	  let () = if !Vine_parser.flag_typecheck then
	    Vine_typecheck.typecheck p else () in 
	  let p = if !flag_alpha then 
		Vine_alphavary.alpha_vary_program p else p in 
	  let p = if !flag_descope then 
		Vine_alphavary.descope_program p else p in 
	    p
	) in 
	let () = if !Vine_parser.flag_pp then 
	  Vine.pp_program (print_string) prog in
	let r = if !flag_evaluate then 
	  (let ce = new Vine_ceval.concrete_evaluator prog in
	   let r = ce#run () in 
	     match r with
	      Vine_ceval.Int(_,x) -> Int64.to_int x
	       | _ -> -1
	  ) else 0 in
	  exit(r)
	  
  )
in
main (Array.length Sys.argv) Sys.argv;;
