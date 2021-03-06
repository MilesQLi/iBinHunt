/********************************************************************
 * AUTHORS: Vijay Ganesh, David L. Dill
 *
 * BEGIN DATE: November, 2005
 *
 * LICENSE: Please view LICENSE file in the home dir of this Program
 ********************************************************************/
// -*- c++ -*-
#ifndef _cvcl__include__c_interface_h_
#define _cvcl__include__c_interface_h_

#ifdef __cplusplus
extern "C" {
#endif
  
#ifdef STP_STRONG_TYPING
#else
  //This gives absolutely no pointer typing at compile-time. Most C
  //users prefer this over stronger typing. User is the king. A
  //stronger typed interface is in the works.
  typedef void* VC;
  typedef void* Expr;
  typedef void* Type;
#endif

  // o  : optimizations
  // c  : check counterexample
  // p  : print counterexample
  // h  : help
  // s  : stats
  // v  : print nodes
  void vc_setFlags(char c);
  
  //! Flags can be NULL
  VC vc_createValidityChecker(void);
  
  // Basic types
  Type vc_boolType(VC vc);
  
  //! Create an array type
  Type vc_arrayType(VC vc, Type typeIndex, Type typeData);

  /////////////////////////////////////////////////////////////////////////////
  // Expr manipulation methods                                               //
  /////////////////////////////////////////////////////////////////////////////

  //! Create a variable with a given name and type 
  /*! The type cannot be a function type. */  
  Expr vc_varExpr(VC vc, char * name, Type type);

  Expr vc_varExpr1(VC vc, char* name, 
		  int indexwidth, int valuewidth);

  //! Get the expression and type associated with a name.
  /*!  If there is no such Expr, a NULL Expr is returned. */
  //Expr vc_lookupVar(VC vc, char* name, Type* type);
  
  //! Get the type of the Expr.
  Type vc_getType(VC vc, Expr e);
  
  //! Create an equality expression.  The two children must have the same type.
  Expr vc_eqExpr(VC vc, Expr child0, Expr child1);
  
  // Boolean expressions
  
  // The following functions create Boolean expressions.  The children provided
  // as arguments must be of type Boolean.
  Expr vc_trueExpr(VC vc);
  Expr vc_falseExpr(VC vc);
  Expr vc_notExpr(VC vc, Expr child);
  Expr vc_andExpr(VC vc, Expr left, Expr right);
  Expr vc_andExprN(VC vc, Expr* children, int numOfChildNodes);
  Expr vc_orExpr(VC vc, Expr left, Expr right);
  Expr vc_orExprN(VC vc, Expr* children, int numOfChildNodes);
  Expr vc_impliesExpr(VC vc, Expr hyp, Expr conc);
  Expr vc_iffExpr(VC vc, Expr left, Expr right);
  Expr vc_iteExpr(VC vc, Expr ifpart, Expr thenpart, Expr elsepart);
  
  //Boolean to single bit BV Expression
  Expr vc_boolToBVExpr(VC vc, Expr form);

  // Arrays
  
  //! Create an expression for the value of array at the given index
  Expr vc_readExpr(VC vc, Expr array, Expr index);

  //! Array update; equivalent to "array WITH [index] := newValue"
  Expr vc_writeExpr(VC vc, Expr array, Expr index, Expr newValue);
  
  // Expr I/O
  //! Expr vc_parseExpr(VC vc, char* s);

  //! Prints 'e' to stdout.
  void vc_printExpr(VC vc, Expr e);

  //! Prints 'e' into an open file descriptor 'fd'
  void vc_printExprFile(VC vc, Expr e, int fd);

  //! Prints state of 'vc' into malloc'd buffer '*buf' and stores the 
  //  length into '*len'.  It is the responsibility of the caller to 
  //  free the buffer.
  void vc_printStateToBuffer(VC vc, char **buf, unsigned long *len);

  //! Prints 'e' to malloc'd buffer '*buf'.  Sets '*len' to the length of 
  //  the buffer. It is the responsibility of the caller to free the buffer.
  void vc_printExprToBuffer(VC vc, Expr e, char **buf, unsigned long * len);

  //! Prints counterexample to stdout.
  void vc_printCounterExample(VC vc);

  //! Prints variable declarations to stdout.
  void vc_printVarDecls(VC vc);

  //! Prints asserts to stdout.
  void vc_printAsserts(VC vc);

  //! Prints the state of the query to malloc'd buffer '*buf' and stores
  //! the length of the buffer to '*len'.  It is the responsibility of the
  //  caller to free the buffer.
  void vc_printQueryStateToBuffer(VC vc, Expr e,char **buf,unsigned long *len);

  //! Prints query to stdout.
  void vc_printQuery(VC vc);

  /////////////////////////////////////////////////////////////////////////////
  // Context-related methods                                                 //
  /////////////////////////////////////////////////////////////////////////////
  
  //! Assert a new formula in the current context.  
  /*! The formula must have Boolean type. */
  void vc_assertFormula(VC vc, Expr e);
  
  //! Simplify e with respect to the current context
  Expr vc_simplify(VC vc, Expr e);
  
  //! Check validity of e in the current context.
  /*!  If the result is true, then the resulting context is the same as
   * the starting context.  If the result is false, then the resulting
   * context is a context in which e is false.  e must have Boolean
   * type. */
  int vc_query(VC vc, Expr e);
  
  //! Return the counterexample after a failed query.
  Expr vc_getCounterExample(VC vc, Expr e);

  //! get size of counterexample, i.e. the number of variables/array
  //locations in the counterexample.
  int vc_counterexample_size(VC vc);
  
  //! Checkpoint the current context and increase the scope level
  void vc_push(VC vc);
  
  //! Restore the current context to its state at the last checkpoint
  void vc_pop(VC vc);
  
  //! Return an int from a constant bitvector expression
  int getBVInt(Expr e);
  //! Return an unsigned int from a constant bitvector expression
  unsigned int getBVUnsigned(Expr e);
  //! Return an unsigned long long int from a constant bitvector expressions
  unsigned long long int getBVUnsignedLongLong(Expr e);
  
  /**************************/
  /* BIT VECTOR OPERATIONS  */
  /**************************/
  Type vc_bvType(VC vc, int no_bits);
  Type vc_bv32Type(VC vc);
  
  Expr vc_bvConstExprFromStr(VC vc, char* binary_repr);
  Expr vc_bvConstExprFromInt(VC vc, int n_bits, unsigned int value);
  Expr vc_bvConstExprFromLL(VC vc, int n_bits, unsigned long long value);
  Expr vc_bv32ConstExprFromInt(VC vc, unsigned int value);
  
  Expr vc_bvConcatExpr(VC vc, Expr left, Expr right);
  Expr vc_bvPlusExpr(VC vc, int n_bits, Expr left, Expr right);
  Expr vc_bv32PlusExpr(VC vc, Expr left, Expr right);
  Expr vc_bvMinusExpr(VC vc, int n_bits, Expr left, Expr right);
  Expr vc_bv32MinusExpr(VC vc, Expr left, Expr right);
  Expr vc_bvMultExpr(VC vc, int n_bits, Expr left, Expr right);
  Expr vc_bv32MultExpr(VC vc, Expr left, Expr right);
  // left divided by right i.e. left/right
  Expr vc_bvDivExpr(VC vc, int n_bits, Expr left, Expr right);
  // left modulo right i.e. left%right
  Expr vc_bvModExpr(VC vc, int n_bits, Expr left, Expr right);
  
  Expr vc_bvLtExpr(VC vc, Expr left, Expr right);
  Expr vc_bvLeExpr(VC vc, Expr left, Expr right);
  Expr vc_bvGtExpr(VC vc, Expr left, Expr right);
  Expr vc_bvGeExpr(VC vc, Expr left, Expr right);
  
  Expr vc_sbvLtExpr(VC vc, Expr left, Expr right);
  Expr vc_sbvLeExpr(VC vc, Expr left, Expr right);
  Expr vc_sbvGtExpr(VC vc, Expr left, Expr right);
  Expr vc_sbvGeExpr(VC vc, Expr left, Expr right);
  
  Expr vc_bvUMinusExpr(VC vc, Expr child);
  
  Expr vc_bvAndExpr(VC vc, Expr left, Expr right);
  Expr vc_bvOrExpr(VC vc, Expr left, Expr right);
  Expr vc_bvXorExpr(VC vc, Expr left, Expr right);
  Expr vc_bvNotExpr(VC vc, Expr child);
  
  Expr vc_bvLeftShiftExpr(VC vc, int sh_amt, Expr child);
  Expr vc_bvRightShiftExpr(VC vc, int sh_amt, Expr child);
  /* Same as vc_bvLeftShift only that the answer in 32 bits long */
  Expr vc_bv32LeftShiftExpr(VC vc, int sh_amt, Expr child);
  /* Same as vc_bvRightShift only that the answer in 32 bits long */
  Expr vc_bv32RightShiftExpr(VC vc, int sh_amt, Expr child);
  Expr vc_bvVar32LeftShiftExpr(VC vc, Expr sh_amt, Expr child);
  Expr vc_bvVar32RightShiftExpr(VC vc, Expr sh_amt, Expr child);
  Expr vc_bvVar32DivByPowOfTwoExpr(VC vc, Expr child, Expr rhs);

  Expr vc_bvExtract(VC vc, Expr child, int high_bit_no, int low_bit_no);
  Expr vc_bvBoolExtract(VC vc, Expr child, int bit_no);
  
  Expr vc_bvSignExtend(VC vc, Expr child, int nbits);
  
  /*C pointer support:  C interface to support C memory arrays in CVCL */
  Expr vc_bvCreateMemoryArray(VC vc, char * arrayName);
  Expr vc_bvReadMemoryArray(VC vc, 
			  Expr array, Expr byteIndex, int numOfBytes);
  Expr vc_bvWriteToMemoryArray(VC vc, 
			       Expr array, Expr  byteIndex, 
			       Expr element, int numOfBytes);
  Expr vc_bv32ConstExprFromInt(VC vc, unsigned int value);
  
  const char* exprString(Expr e);
  
  const char* typeString(Type t);

  Expr getChild(Expr e, int i);

  /* Register the given error handler to be called for each fatal error.*/
  void vc_registerErrorHandler(void (*error_hdlr)(const char* err_msg));

#ifdef __cplusplus
};
#endif

#endif


