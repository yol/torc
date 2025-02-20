// -*- C++ -*-
//*************************************************************************
// DESCRIPTION: Verilator: Bison grammer file
//
// Code available from: http://www.veripool.org/verilator
//
//*************************************************************************
//
// Copyright 2003-2012 by Wilson Snyder.  This program is free software; you can
// redistribute it and/or modify it under the terms of either the GNU
// Lesser General Public License Version 3 or the Perl Artistic License
// Version 2.0.
//
// Verilator is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
//*************************************************************************
// Original code here by Paul Wasson and Duane Galbi
//*************************************************************************

%{
#include <cstdio>
#include <cstdlib>
#include <cstdarg>
#include <cstring>

#include "V3Ast.h"
#include "V3Global.h"
#include "V3Config.h"
#include "V3ParseImp.h"  // Defines YYTYPE; before including bison header

#define YYERROR_VERBOSE 1
#define YYINITDEPTH 10000	// Older bisons ignore YYMAXDEPTH
#define YYMAXDEPTH 10000

// Pick up new lexer
#define yylex PARSEP->lexToBison
#define GATEUNSUP(fl,tok) { if (!v3Global.opt.bboxUnsup()) { (fl)->v3error("Unsupported: Verilog 1995 gate primitive: "<<(tok)); } }

extern void yyerror(const char* errmsg);
extern void yyerrorf(const char* format, ...);

//======================================================================
// Statics (for here only)

#define PARSEP V3ParseImp::parsep()
#define SYMP PARSEP->symp()
#define GRAMMARP V3ParseGrammar::singletonp()

class V3ParseGrammar {
public:
    bool	m_impliedDecl;	// Allow implied wire declarations
    AstVarType	m_varDecl;	// Type for next signal declaration (reg/wire/etc)
    AstVarType	m_varIO;	// Type for next signal declaration (input/output/etc)
    AstVar*	m_varAttrp;	// Current variable for attribute adding
    AstCase*	m_caseAttrp;	// Current case statement for attribute adding
    AstNodeDType* m_varDTypep;	// Pointer to data type for next signal declaration
    int		m_pinNum;	// Pin number currently parsing
    string	m_instModule;	// Name of module referenced for instantiations
    AstPin*	m_instParamp;	// Parameters for instantiations
    AstNodeModule* m_modp;	// Module
    int		m_modTypeImpNum; // Implicit type number, incremented each module
    int		m_uniqueAttr;	// Bitmask of unique/priority keywords

    // CONSTRUCTORS
    V3ParseGrammar() {
	m_impliedDecl = false;
	m_varDecl = AstVarType::UNKNOWN;
	m_varIO = AstVarType::UNKNOWN;
	m_varDTypep = NULL;
	m_pinNum = -1;
	m_instModule = "";
	m_instParamp = NULL;
	m_modp = NULL;
	m_modTypeImpNum = 0;
	m_varAttrp = NULL;
	m_caseAttrp = NULL;
    }
    static V3ParseGrammar* singletonp() {
	static V3ParseGrammar singleton;
	return &singleton;
    }

    // METHODS
    AstNodeDType* createArray(AstNodeDType* basep, AstRange* rangep, bool isPacked);
    AstVar*  createVariable(FileLine* fileline, string name, AstRange* arrayp, AstNode* attrsp);
    AstNode* createSupplyExpr(FileLine* fileline, string name, int value);
    AstText* createTextQuoted(FileLine* fileline, string text) {
	string newtext = deQuote(fileline, text);
	return new AstText(fileline, newtext);
    }
    AstDisplay* createDisplayError(FileLine* fileline) {
	AstDisplay* nodep = new AstDisplay(fileline,AstDisplayType::DT_ERROR,  "", NULL,NULL);
	nodep->addNext(new AstStop(fileline));
	return nodep;
    }
    void endLabel(FileLine* fl, AstNode* nodep, string* endnamep) { endLabel(fl, nodep->prettyName(), endnamep); }
    void endLabel(FileLine* fl, string name, string* endnamep) {
	if (fl && endnamep && *endnamep != "" && name != *endnamep) {
	    fl->v3warn(ENDLABEL,"End label '"<<*endnamep<<"' does not match begin label '"<<name<<"'");
	}
    }
    void setDType(AstNodeDType* dtypep) {
	if (m_varDTypep) { m_varDTypep->deleteTree(); m_varDTypep=NULL; } // It was cloned, so this is safe.
	m_varDTypep = dtypep;
    }
    AstPackage* unitPackage(FileLine* fl) {	
	// Find one made earlier?
	AstPackage* pkgp = SYMP->symRootp()->findIdFlat(AstPackage::dollarUnitName())->castPackage();
	if (!pkgp) {
	    pkgp = new AstPackage(fl, AstPackage::dollarUnitName());
	    pkgp->inLibrary(true);  // packages are always libraries; don't want to make them a "top"
	    pkgp->modTrace(false);  // may reconsider later
	    GRAMMARP->m_modp = pkgp; GRAMMARP->m_modTypeImpNum = 0;
	    PARSEP->rootp()->addModulep(pkgp);
	    SYMP->reinsert(pkgp, SYMP->symRootp());  // Don't push/pop scope as they're global
	}
	return pkgp;
    }
    AstNodeDType* addRange(AstBasicDType* dtypep, AstRange* rangesp, bool isPacked) {
	// If dtypep isn't basic, don't use this, call createArray() instead
	if (!rangesp) {
	    return dtypep;
	} else {
	    // If rangesp is "wire [3:3][2:2][1:1] foo [5:5][4:4]"
	    // then [1:1] becomes the basicdtype range; everything else is arraying
	    // the final [5:5][4:4] will be passed in another call to createArray
	    AstRange* rangearraysp = NULL;
	    if (dtypep->isRanged()) {
		rangearraysp = rangesp;  // Already a range; everything is an array
	    } else {
		AstRange* finalp = rangesp;
		while (finalp->nextp()) finalp=finalp->nextp()->castRange();
		if (finalp != rangesp) {
		    finalp->unlinkFrBack();
		    rangearraysp = rangesp;
		}
		dtypep->rangep(finalp);
	       	dtypep->implicit(false);
	    }
	    return createArray(dtypep, rangearraysp, isPacked);
	}
    }
    string   deQuote(FileLine* fileline, string text);
    void checkDpiVer(FileLine* fileline, const string& str) {
	if (str != "DPI-C" && !v3Global.opt.bboxSys()) {
	    fileline->v3error("Unsupported DPI type '"<<str<<"': Use 'DPI-C'");
	}
    }
};

const AstBasicDTypeKwd LOGIC = AstBasicDTypeKwd::LOGIC;	// Shorthand "LOGIC"
const AstBasicDTypeKwd LOGIC_IMPLICIT = AstBasicDTypeKwd::LOGIC_IMPLICIT;

//======================================================================
// Macro functions

#define CRELINE() (PARSEP->copyOrSameFileLine())  // Only use in empty rules, so lines point at beginnings

#define VARRESET_LIST(decl)    { GRAMMARP->m_pinNum=1; VARRESET(); VARDECL(decl); }	// Start of pinlist
#define VARRESET_NONLIST(decl) { GRAMMARP->m_pinNum=0; VARRESET(); VARDECL(decl); }	// Not in a pinlist
#define VARRESET() { VARDECL(UNKNOWN); VARIO(UNKNOWN); VARDTYPE(NULL); }
#define VARDECL(type) { GRAMMARP->m_varDecl = AstVarType::type; }
#define VARIO(type) { GRAMMARP->m_varIO = AstVarType::type; }
#define VARDTYPE(dtypep) { GRAMMARP->setDType(dtypep); }

#define VARDONEA(fl,name,array,attrs) GRAMMARP->createVariable((fl),(name),(array),(attrs))
#define VARDONEP(portp,array,attrs) GRAMMARP->createVariable((portp)->fileline(),(portp)->name(),(array),(attrs))
#define PINNUMINC() (GRAMMARP->m_pinNum++)

#define INSTPREP(modname,paramsp) { GRAMMARP->m_impliedDecl = true; GRAMMARP->m_instModule = modname; GRAMMARP->m_instParamp = paramsp; }

static void ERRSVKWD(FileLine* fileline, const string& tokname) {
    static int toldonce = 0;
    fileline->v3error((string)"Unexpected \""+tokname+"\": \""+tokname+"\" is a SystemVerilog keyword misused as an identifier.");
    if (!toldonce++) fileline->v3error("Modify the Verilog-2001 code to avoid SV keywords, or use `begin_keywords or --language.");
}

//======================================================================

class AstSenTree;
%}

// When writing Bison patterns we use yTOKEN instead of "token",
// so Bison will error out on unknown "token"s.

// Generic lexer tokens, for example a number
// IEEE: real_number
%token<cdouble>		yaFLOATNUM	"FLOATING-POINT NUMBER"

// IEEE: identifier, class_identifier, class_variable_identifier,
// covergroup_variable_identifier, dynamic_array_variable_identifier,
// enum_identifier, interface_identifier, interface_instance_identifier,
// package_identifier, type_identifier, variable_identifier,
%token<strp>		yaID__ETC	"IDENTIFIER"
%token<strp>		yaID__LEX	"IDENTIFIER-in-lex"
%token<strp>		yaID__aPACKAGE	"PACKAGE-IDENTIFIER"
%token<strp>		yaID__aTYPE	"TYPE-IDENTIFIER"

// IEEE: integral_number
%token<nump>		yaINTNUM	"INTEGER NUMBER"
// IEEE: time_literal + time_unit
%token<cdouble>		yaTIMENUM	"TIME NUMBER"
// IEEE: string_literal
%token<strp>		yaSTRING	"STRING"
%token<strp>		yaSTRING__IGNORE "STRING-ignored"	// Used when expr:string not allowed

%token<fl>		yaTIMINGSPEC	"TIMING SPEC ELEMENT"

%token<strp>		yaTABLELINE	"TABLE LINE"

%token<strp>		yaSCHDR		"`systemc_header BLOCK"
%token<strp>		yaSCINT		"`systemc_ctor BLOCK"
%token<strp>		yaSCIMP		"`systemc_dtor BLOCK"
%token<strp>		yaSCIMPH	"`systemc_interface BLOCK"
%token<strp>		yaSCCTOR	"`systemc_implementation BLOCK"
%token<strp>		yaSCDTOR	"`systemc_imp_header BLOCK"

%token<fl>		yVLT_COVERAGE_OFF "coverage_off"
%token<fl>		yVLT_LINT_OFF	"lint_off"
%token<fl>		yVLT_TRACING_OFF "tracing_off"

%token<fl>		yVLT_D_FILE	"--file"
%token<fl>		yVLT_D_LINES	"--lines"
%token<fl>		yVLT_D_MSG	"--msg"

%token<strp>		yaD_IGNORE	"${ignored-bbox-sys}"
%token<strp>		yaD_DPI		"${dpi-sys}"

// <fl> is the fileline, abbreviated to shorten "$<fl>1" references
%token<fl>		'!'
%token<fl>		'#'
%token<fl>		'%'
%token<fl>		'&'
%token<fl>		'('
%token<fl>		')'
%token<fl>		'*'
%token<fl>		'+'
%token<fl>		','
%token<fl>		'-'
%token<fl>		'.'
%token<fl>		'/'
%token<fl>		':'
%token<fl>		';'
%token<fl>		'<'
%token<fl>		'='
%token<fl>		'>'
%token<fl>		'?'
%token<fl>		'@'
%token<fl>		'['
%token<fl>		']'
%token<fl>		'^'
%token<fl>		'{'
%token<fl>		'|'
%token<fl>		'}'
%token<fl>		'~'

// Specific keywords
// yKEYWORD means match "keyword"
// Other cases are yXX_KEYWORD where XX makes it unique,
// for example yP_ for punctuation based operators.
// Double underscores "yX__Y" means token X followed by Y,
// and "yX__ETC" means X folled by everything but Y(s).
%token<fl>		yALWAYS		"always"
%token<fl>		yAND		"and"
%token<fl>		yASSERT		"assert"
%token<fl>		yASSIGN		"assign"
%token<fl>		yAUTOMATIC	"automatic"
%token<fl>		yBEGIN		"begin"
%token<fl>		yBIT		"bit"
%token<fl>		yBREAK		"break"
%token<fl>		yBUF		"buf"
%token<fl>		yBUFIF0		"bufif0"
%token<fl>		yBUFIF1		"bufif1"
%token<fl>		yBYTE		"byte"
%token<fl>		yCASE		"case"
%token<fl>		yCASEX		"casex"
%token<fl>		yCASEZ		"casez"
%token<fl>		yCHANDLE	"chandle"
%token<fl>		yCLOCKING	"clocking"
%token<fl>		yCONST__ETC	"const"
%token<fl>		yCONST__LEX	"const-in-lex"
%token<fl>		yCMOS		"cmos"
%token<fl>		yCONTEXT	"context"
%token<fl>		yCONTINUE	"continue"
%token<fl>		yCOVER		"cover"
%token<fl>		yDEFAULT	"default"
%token<fl>		yDEFPARAM	"defparam"
%token<fl>		yDISABLE	"disable"
%token<fl>		yDO		"do"
%token<fl>		yEDGE		"edge"
%token<fl>		yELSE		"else"
%token<fl>		yEND		"end"
%token<fl>		yENDCASE	"endcase"
%token<fl>		yENDCLOCKING	"endclocking"
%token<fl>		yENDFUNCTION	"endfunction"
%token<fl>		yENDGENERATE	"endgenerate"
%token<fl>		yENDMODULE	"endmodule"
%token<fl>		yENDPACKAGE	"endpackage"
%token<fl>		yENDPRIMITIVE	"endprimitive"
%token<fl>		yENDPROGRAM	"endprogram"
%token<fl>		yENDPROPERTY	"endproperty"
%token<fl>		yENDSPECIFY	"endspecify"
%token<fl>		yENDTABLE	"endtable"
%token<fl>		yENDTASK	"endtask"
%token<fl>		yENUM		"enum"
%token<fl>		yEXPORT		"export"
%token<fl>		yFINAL		"final"
%token<fl>		yFOR		"for"
%token<fl>		yFOREVER	"forever"
%token<fl>		yFUNCTION	"function"
%token<fl>		yGENERATE	"generate"
%token<fl>		yGENVAR		"genvar"
%token<fl>		yGLOBAL__CLOCKING "global-then-clocking"
%token<fl>		yGLOBAL__LEX	"global-in-lex"
%token<fl>		yIF		"if"
%token<fl>		yIFF		"iff"
%token<fl>		yIMPORT		"import"
%token<fl>		yINITIAL	"initial"
%token<fl>		yINOUT		"inout"
%token<fl>		yINPUT		"input"
%token<fl>		yINT		"int"
%token<fl>		yINTEGER	"integer"
%token<fl>		yLOCALPARAM	"localparam"
%token<fl>		yLOGIC		"logic"
%token<fl>		yLONGINT	"longint"
%token<fl>		yMODULE		"module"
%token<fl>		yNAND		"nand"
%token<fl>		yNEGEDGE	"negedge"
%token<fl>		yNMOS		"nmos"
%token<fl>		yNOR		"nor"
%token<fl>		yNOT		"not"
%token<fl>		yNOTIF0		"notif0"
%token<fl>		yNOTIF1		"notif1"
%token<fl>		yOR		"or"
%token<fl>		yOUTPUT		"output"
%token<fl>		yPACKAGE	"package"
%token<fl>		yPARAMETER	"parameter"
%token<fl>		yPMOS		"pmos"
%token<fl>		yPOSEDGE	"posedge"
%token<fl>		yPRIMITIVE	"primitive"
%token<fl>		yPRIORITY	"priority"
%token<fl>		yPROGRAM	"program"
%token<fl>		yPROPERTY	"property"
%token<fl>		yPULLDOWN	"pulldown"
%token<fl>		yPULLUP		"pullup"
%token<fl>		yPURE		"pure"
%token<fl>		yRCMOS		"rcmos"
%token<fl>		yREAL		"real"
%token<fl>		yREALTIME	"realtime"
%token<fl>		yREG		"reg"
%token<fl>		yREPEAT		"repeat"
%token<fl>		yRETURN		"return"
%token<fl>		yRNMOS		"rnmos"
%token<fl>		yRPMOS		"rpmos"
%token<fl>		yRTRAN		"rtran"
%token<fl>		yRTRANIF0	"rtranif0"
%token<fl>		yRTRANIF1	"rtranif1"
%token<fl>		ySCALARED	"scalared"
%token<fl>		ySHORTINT	"shortint"
%token<fl>		ySIGNED		"signed"
%token<fl>		ySPECIFY	"specify"
%token<fl>		ySPECPARAM	"specparam"
%token<fl>		ySTATIC		"static"
%token<fl>		ySTRING		"string"
%token<fl>		ySUPPLY0	"supply0"
%token<fl>		ySUPPLY1	"supply1"
%token<fl>		yTABLE		"table"
%token<fl>		yTASK		"task"
%token<fl>		yTIME		"time"
%token<fl>		yTIMEPRECISION	"timeprecision"
%token<fl>		yTIMEUNIT	"timeunit"
%token<fl>		yTRAN		"tran"
%token<fl>		yTRANIF0	"tranif0"
%token<fl>		yTRANIF1	"tranif1"
%token<fl>		yTRI		"tri"
%token<fl>		yTRUE		"true"
%token<fl>		yTYPEDEF	"typedef"
%token<fl>		yUNIQUE		"unique"
%token<fl>		yUNIQUE0	"unique0"
%token<fl>		yUNSIGNED	"unsigned"
%token<fl>		yVAR		"var"
%token<fl>		yVECTORED	"vectored"
%token<fl>		yVOID		"void"
%token<fl>		yWHILE		"while"
%token<fl>		yWIRE		"wire"
%token<fl>		yWREAL		"wreal"
%token<fl>		yXNOR		"xnor"
%token<fl>		yXOR		"xor"

%token<fl>		yD_BITS		"$bits"
%token<fl>		yD_BITSTOREAL	"$bitstoreal"
%token<fl>		yD_C		"$c"
%token<fl>		yD_CEIL		"$ceil"
%token<fl>		yD_CLOG2	"$clog2"
%token<fl>		yD_COUNTONES	"$countones"
%token<fl>		yD_DISPLAY	"$display"
%token<fl>		yD_ERROR	"$error"
%token<fl>		yD_EXP		"$exp"
%token<fl>		yD_FATAL	"$fatal"
%token<fl>		yD_FCLOSE	"$fclose"
%token<fl>		yD_FDISPLAY	"$fdisplay"
%token<fl>		yD_FEOF		"$feof"
%token<fl>		yD_FFLUSH	"$fflush"
%token<fl>		yD_FGETC	"$fgetc"
%token<fl>		yD_FGETS	"$fgets"
%token<fl>		yD_FINISH	"$finish"
%token<fl>		yD_FLOOR	"$floor"
%token<fl>		yD_FOPEN	"$fopen"
%token<fl>		yD_FSCANF	"$fscanf"
%token<fl>		yD_FWRITE	"$fwrite"
%token<fl>		yD_INFO		"$info"
%token<fl>		yD_ISUNKNOWN	"$isunknown"
%token<fl>		yD_ITOR		"$itor"
%token<fl>		yD_LN		"$ln"
%token<fl>		yD_LOG10	"$log10"
%token<fl>		yD_ONEHOT	"$onehot"
%token<fl>		yD_ONEHOT0	"$onehot0"
%token<fl>		yD_POW		"$pow"
%token<fl>		yD_RANDOM	"$random"
%token<fl>		yD_READMEMB	"$readmemb"
%token<fl>		yD_READMEMH	"$readmemh"
%token<fl>		yD_REALTIME	"$realtime"
%token<fl>		yD_REALTOBITS	"$realtobits"
%token<fl>		yD_RTOI		"$rtoi"
%token<fl>		yD_SFORMAT	"$sformat"
%token<fl>		yD_SIGNED	"$signed"
%token<fl>		yD_SQRT		"$sqrt"
%token<fl>		yD_SSCANF	"$sscanf"
%token<fl>		yD_STIME	"$stime"
%token<fl>		yD_STOP		"$stop"
%token<fl>		yD_SWRITE	"$swrite"
%token<fl>		yD_SYSTEM	"$system"
%token<fl>		yD_TESTPLUSARGS	"$test$plusargs"
%token<fl>		yD_TIME		"$time"
%token<fl>		yD_UNIT		"$unit"
%token<fl>		yD_UNSIGNED	"$unsigned"
%token<fl>		yD_VALUEPLUSARGS "$value$plusargs"
%token<fl>		yD_WARNING	"$warning"
%token<fl>		yD_WRITE	"$write"

%token<fl>		yPSL		"psl"
%token<fl>		yPSL_ASSERT	"PSL assert"
%token<fl>		yPSL_CLOCK	"PSL clock"
%token<fl>		yPSL_COVER	"PSL cover"
%token<fl>		yPSL_REPORT	"PSL report"

%token<fl>		yVL_CLOCK		"/*verilator sc_clock*/"
%token<fl>		yVL_CLOCK_ENABLE	"/*verilator clock_enable*/"
%token<fl>		yVL_COVERAGE_BLOCK_OFF	"/*verilator coverage_block_off*/"
%token<fl>		yVL_FULL_CASE		"/*verilator full_case*/"
%token<fl>		yVL_INLINE_MODULE	"/*verilator inline_module*/"
%token<fl>		yVL_ISOLATE_ASSIGNMENTS	"/*verilator isolate_assignments*/"
%token<fl>		yVL_NO_INLINE_MODULE	"/*verilator no_inline_module*/"
%token<fl>		yVL_NO_INLINE_TASK	"/*verilator no_inline_task*/"
%token<fl>		yVL_SC_BV		"/*verilator sc_bv*/"
%token<fl>		yVL_SFORMAT		"/*verilator sformat*/"
%token<fl>		yVL_PARALLEL_CASE	"/*verilator parallel_case*/"
%token<fl>		yVL_PUBLIC		"/*verilator public*/"
%token<fl>		yVL_PUBLIC_FLAT		"/*verilator public_flat*/"
%token<fl>		yVL_PUBLIC_FLAT_RD	"/*verilator public_flat_rd*/"
%token<fl>		yVL_PUBLIC_FLAT_RW	"/*verilator public_flat_rw*/"
%token<fl>		yVL_PUBLIC_MODULE	"/*verilator public_module*/"

%token<fl>		yP_TICK		"'"
%token<fl>		yP_TICKBRA	"'{"
%token<fl>		yP_OROR		"||"
%token<fl>		yP_ANDAND	"&&"
%token<fl>		yP_NOR		"~|"
%token<fl>		yP_XNOR		"^~"
%token<fl>		yP_NAND		"~&"
%token<fl>		yP_EQUAL	"=="
%token<fl>		yP_NOTEQUAL	"!="
%token<fl>		yP_CASEEQUAL	"==="
%token<fl>		yP_CASENOTEQUAL	"!=="
%token<fl>		yP_WILDEQUAL	"==?"
%token<fl>		yP_WILDNOTEQUAL	"!=?"
%token<fl>		yP_GTE		">="
%token<fl>		yP_LTE		"<="
%token<fl>		yP_SLEFT	"<<"
%token<fl>		yP_SRIGHT	">>"
%token<fl>		yP_SSRIGHT	">>>"
%token<fl>		yP_POW		"**"

%token<fl>		yP_PLUSCOLON	"+:"
%token<fl>		yP_MINUSCOLON	"-:"
%token<fl>		yP_MINUSGT	"->"
%token<fl>		yP_MINUSGTGT	"->>"
%token<fl>		yP_EQGT		"=>"
%token<fl>		yP_ASTGT	"*>"
%token<fl>		yP_ANDANDAND	"&&&"
%token<fl>		yP_POUNDPOUND	"##"
%token<fl>		yP_DOTSTAR	".*"

%token<fl>		yP_ATAT		"@@"
%token<fl>		yP_COLONCOLON	"::"
%token<fl>		yP_COLONEQ	":="
%token<fl>		yP_COLONDIV	":/"
%token<fl>		yP_ORMINUSGT	"|->"
%token<fl>		yP_OREQGT	"|=>"
%token<fl>		yP_BRASTAR	"[*"
%token<fl>		yP_BRAEQ	"[="
%token<fl>		yP_BRAMINUSGT	"[->"

%token<fl>		yP_PLUSPLUS	"++"
%token<fl>		yP_MINUSMINUS	"--"
%token<fl>		yP_PLUSEQ	"+="
%token<fl>		yP_MINUSEQ	"-="
%token<fl>		yP_TIMESEQ	"*="
%token<fl>		yP_DIVEQ	"/="
%token<fl>		yP_MODEQ	"%="
%token<fl>		yP_ANDEQ	"&="
%token<fl>		yP_OREQ		"|="
%token<fl>		yP_XOREQ	"^="
%token<fl>		yP_SLEFTEQ	"<<="
%token<fl>		yP_SRIGHTEQ	">>="
%token<fl>		yP_SSRIGHTEQ	">>>="

%token<fl>		yPSL_BRA	"{"
%token<fl>		yPSL_KET	"}"
%token<fl>	 	yP_LOGIFF

// [* is not a operator, as "[ * ]" is legal
// [= and [-> could be repitition operators, but to match [* we don't add them.
// '( is not a operator, as "' (" is legal

//********************
// PSL op precedence
%right	 	yP_MINUSGT  yP_LOGIFF
%right		yP_ORMINUSGT  yP_OREQGT
%left<fl>		prPSLCLK

// Verilog op precedence
%right		'?' ':'
%left		yP_OROR
%left		yP_ANDAND
%left		'|' yP_NOR
%left		'^' yP_XNOR
%left		'&' yP_NAND
%left		yP_EQUAL yP_NOTEQUAL yP_CASEEQUAL yP_CASENOTEQUAL yP_WILDEQUAL yP_WILDNOTEQUAL
%left		'>' '<' yP_GTE yP_LTE
%left		yP_SLEFT yP_SRIGHT yP_SSRIGHT
%left		'+' '-'
%left		'*' '/' '%'
%left		yP_POW
%left		prUNARYARITH yP_MINUSMINUS yP_PLUSPLUS prREDUCTION prNEGATION
%left		'.'
// Not in IEEE, but need to avoid conflicts; TICK should bind tightly just lower than COLONCOLON
%left		yP_TICK
//%left		'(' ')' '[' ']' yP_COLONCOLON '.'

%nonassoc prLOWER_THAN_ELSE
%nonassoc yELSE

//BISONPRE_TYPES
%type<bdtypep>	 integer_atom_type integer_vector_type non_integer_type
%type<beginp>	 seq_blockFront
%type<caseitemp>	 case_itemList case_itemListE
%type<casep>	 caseStart
%type<cint>	 funcIsolateE
%type<dtypep>	 casting_type data_type data_typeBasic data_typeNoRef delayrange enumDecl enum_base_typeE implicit_typeE ps_type simple_type wirerangeE
%type<errcodeen>	 vltOffFront
%type<fl>	 delay_control
%type<ftaskp>	 funcId function_declaration function_prototype taskId task_declaration task_prototype
%type<ftaskrefp>	 funcRef taskRef
%type<iprop>	 dpi_tf_import_propertyE
%type<modulep>	 modFront packageFront pgmFront udpFront
%type<nodep>	 argsExprList assignList assignOne blockDeclStmtList block_item_declaration block_item_declarationList cStrList caseCondList case_generate_item case_generate_itemList case_generate_itemListE cateList clocking_declaration commaEListE commaVRDListE concurrent_assertion_item concurrent_assertion_statement conditional_generate_construct constExpr continuous_assign data_declaration data_declarationVar defparam_assignment dpi_import_export enumNameRangeE enumNameStartE enum_nameList enum_name_declaration etcInst expr exprList exprNoStr exprOkLvalue exprPsl exprScope exprStrText final_construct finc_or_dec_expression foperator_assignment for_initialization for_step for_stepE function_subroutine_callNoMethod gateAnd gateAndList gateAndPinList gateBuf gateBufList gateBufif0 gateBufif0List gateBufif1 gateBufif1List gateDecl gateNand gateNandList gateNor gateNorList gateNot gateNotList gateNotif0 gateNotif0List gateNotif1 gateNotif1List gateOr gateOrList gateOrPinList gatePulldown gatePulldownList gatePullup gatePullupList gateUnsup gateUnsupList gateUnsupPinList gateXnor gateXnorList gateXor gateXorList gateXorPinList genItem genItemBegin genItemList genTopBlock generate_block_or_null generate_region genvar_declaration genvar_initialization genvar_iteration idArrayed idDotted idDottedMore immediate_assert_statement initial_construct instDecl instnameList instnameParen intnumAsConst labeledStmt list_of_argumentsE list_of_defparam_assignments list_of_genvar_identifiers list_of_ports list_of_tf_variable_identifiers list_of_variable_decl_assignments local_parameter_declaration loop_generate_construct module_common_item module_item module_itemList module_itemListE module_or_generate_item module_or_generate_item_declaration net_declaration non_port_module_item non_port_program_item package_import_declaration package_import_item package_import_itemList package_item package_itemList package_itemListE package_or_generate_item_declaration paramPortDeclOrArg paramPortDeclOrArgList parameter_declaration parameter_port_listE port portSig port_declaration portsStarE program_generate_item program_item program_itemList program_itemListE property_spec pslDecl pslDir pslDirOne pslExpr pslProp pslSequence pslSere pslStmt seq_block sigAttr sigAttrList sigAttrListE specify_block specparam_declaration statementVerilatorPragmas statement_item stmt stmtBlock stmtList strAsInt strAsIntIgnore strAsText stream_expression system_f_call system_t_call table tableEntry tableEntryList task_subroutine_callNoMethod tfBodyE tfGuts tf_item_declaration tf_item_declarationList tf_item_declarationVerilator tf_port_declaration tf_port_item tf_port_listE tf_port_listList timeunits_declaration type_declaration variable_declExpr variable_lvalue variable_lvalueConcList vrdList
%type<packagep>	 package_scopeIdFollows package_scopeIdFollowsE
%type<parserefp>	 idClassSel varRefMem
%type<pinp>	 cellpinItList cellpinItemE cellpinList parameter_value_assignmentE
%type<rangep>	 anyrange instRangeE packed_dimension packed_dimensionList packed_dimensionListE rangeList rangeListE variable_dimension variable_dimensionList variable_dimensionListE
%type<senitemp>	 event_expression senitem senitemEdge senitemVar
%type<sentreep>	 attr_event_control event_control event_controlE
%type<signstate>	 signing signingE
%type<strp>	 dpi_importLabelE endLabelE id idAny idSVKwd netId package_import_itemObj str tfIdScoped
%type<uniqstate>	 unique_priorityE
%type<varp>	 genvar_identifierDecl list_of_param_assignments netSig netSigList param_assignment sigId tf_port_itemAssignment tf_variable_identifier variable_decl_assignment
%type<varrefp>	 varRefBase
//  Blank lines for type insertion

%start source_text

%%
//**********************************************************************
// Feedback to the Lexer
// Note we read a parenthesis ahead, so this may not change the lexer at the right point.

stateExitPsl:			// For PSL lexing, return from PSL state
		/* empty */			 	{ PARSEP->stateExitPsl(); }
	;
statePushVlg:			// For PSL lexing, escape current state into Verilog state
		/* empty */			 	{ PARSEP->statePushVlg(); }
	;
statePop:			// Return to previous lexing state
		/* empty */			 	{ PARSEP->statePop(); }
	;

//**********************************************************************
// Files

source_text:			// ==IEEE: source_text
		/* empty */				{ }
	//			// timeunits_declaration moved into description:package_item
	|	descriptionList				{ }
	;

descriptionList:		// IEEE: part of source_text
		description				{ }
	|	descriptionList description		{ }
	;

description:			// ==IEEE: description
		module_declaration			{ }
	//UNSUP	interface_declaration			{ }
	|	program_declaration			{ }
	|	package_declaration			{ }
	|	package_item				{ if ($1) GRAMMARP->unitPackage($1->fileline())->addStmtp($1); }
	//UNSUP	bind_directive				{ }
	//	unsupported	// IEEE: config_declaration
				// Verilator only
	|	vltItem					{ }
	|	error					{ }
	;

timeunits_declaration:	// ==IEEE: timeunits_declaration
		yTIMEUNIT       yaTIMENUM ';'		{ $$ = NULL; }
	| 	yTIMEPRECISION  yaTIMENUM ';'		{ $$ = NULL; }
	;

//**********************************************************************
// Packages

package_declaration:		// ==IEEE: package_declaration
		packageFront package_itemListE yENDPACKAGE endLabelE
			{ $1->modTrace(v3Global.opt.trace() && $1->fileline()->tracingOn());  // Stash for implicit wires, etc
			  if ($2) $1->addStmtp($2);
			  SYMP->popScope($1);
			  GRAMMARP->endLabel($<fl>4,$1,$4); }
	;

packageFront:
		yPACKAGE idAny ';'
			{ $$ = new AstPackage($1,*$2);
			  $$->inLibrary(true);  // packages are always libraries; don't want to make them a "top"
			  $$->modTrace(v3Global.opt.trace());
			  GRAMMARP->m_modp = $$; GRAMMARP->m_modTypeImpNum = 0;
			  PARSEP->rootp()->addModulep($$);
			  SYMP->pushNew($$); }
	;

package_itemListE:	// IEEE: [{ package_item }]
		/* empty */				{ $$ = NULL; }
	|	package_itemList			{ $$ = $1; }
	;

package_itemList:	// IEEE: { package_item }
		package_item				{ $$ = $1; }
	|	package_itemList package_item		{ $$ = $1->addNextNull($2); }
	;

package_item:		// ==IEEE: package_item
		package_or_generate_item_declaration	{ $$ = $1; }
	//UNSUP	anonymous_program			{ $$ = $1; }
	|	timeunits_declaration			{ $$ = $1; }
	;

package_or_generate_item_declaration:	// ==IEEE: package_or_generate_item_declaration
		net_declaration				{ $$ = $1; }
	|	data_declaration			{ $$ = $1; }
	|	task_declaration			{ $$ = $1; }
	|	function_declaration			{ $$ = $1; }
	|	dpi_import_export			{ $$ = $1; }
	//UNSUP	extern_constraint_declaration		{ $$ = $1; }
	//UNSUP	class_declaration			{ $$ = $1; }
	//			// class_constructor_declaration is part of function_declaration
	|	parameter_declaration ';'		{ $$ = $1; }
	|	local_parameter_declaration		{ $$ = $1; }
	//UNSUP	covergroup_declaration			{ $$ = $1; }
	//UNSUP	overload_declaration			{ $$ = $1; }
	//UNSUP	concurrent_assertion_item_declaration	{ $$ = $1; }
	|	';'					{ $$ = NULL; }
	;

package_import_declaration:	// ==IEEE: package_import_declaration
		yIMPORT package_import_itemList ';'	{ $$ = $2; }
	;

package_import_itemList:
		package_import_item			{ $$ = $1; }
	|	package_import_itemList ',' package_import_item { $$ = $1->addNextNull($3); }
	;

package_import_item:	// ==IEEE: package_import_item
		yaID__aPACKAGE yP_COLONCOLON package_import_itemObj
			{ $$ = new AstPackageImport($<fl>1, $<scp>1->castPackage(), *$3);
			  SYMP->import($<scp>1,*$3); }
	;

package_import_itemObj:	// IEEE: part of package_import_item
		idAny					{ $<fl>$=$<fl>1; $$=$1; }
	|	'*'					{ $<fl>$=$<fl>1; static string star="*"; $$=&star; }
	;

//**********************************************************************
// Module headers

module_declaration:		// ==IEEE: module_declaration
	//			// timeunits_declaration instead in module_item
	//			// IEEE: module_nonansi_header + module_ansi_header
		modFront parameter_port_listE portsStarE ';'
			module_itemListE yENDMODULE endLabelE
			{ $1->modTrace(v3Global.opt.trace() && $1->fileline()->tracingOn());  // Stash for implicit wires, etc
			  if ($2) $1->addStmtp($2); if ($3) $1->addStmtp($3);
			  if ($5) $1->addStmtp($5);
			  SYMP->popScope($1);
			  GRAMMARP->endLabel($<fl>7,$1,$7); }
	|	udpFront parameter_port_listE portsStarE ';'
			module_itemListE yENDPRIMITIVE endLabelE
			{ $1->modTrace(false);  // Stash for implicit wires, etc
			  if ($2) $1->addStmtp($2); if ($3) $1->addStmtp($3);
			  if ($5) $1->addStmtp($5);
			  SYMP->popScope($1);
			  GRAMMARP->endLabel($<fl>7,$1,$7); }
	//
	//UNSUP	yEXTERN modFront parameter_port_listE portsStarE ';'
	//UNSUP		{ UNSUP }
	;

modFront:
	//			// General note: all *Front functions must call symPushNew before
	//			// any formal arguments, as the arguments must land in the new scope.
		yMODULE lifetimeE idAny
			{ $$ = new AstModule($1,*$3); $$->inLibrary(PARSEP->inLibrary()||PARSEP->inCellDefine());
			  $$->modTrace(v3Global.opt.trace());
			  GRAMMARP->m_modp = $$; GRAMMARP->m_modTypeImpNum = 0;
			  PARSEP->rootp()->addModulep($$);
			  SYMP->pushNew($$); }
	;

udpFront:
		yPRIMITIVE lifetimeE idAny
			{ $$ = new AstPrimitive($1,*$3); $$->inLibrary(true);
			  $$->modTrace(false);
			  $$->addStmtp(new AstPragma($1,AstPragmaType::INLINE_MODULE));
			  PARSEP->fileline()->tracingOn(false);
			  GRAMMARP->m_modp = $$; GRAMMARP->m_modTypeImpNum = 0;
			  PARSEP->rootp()->addModulep($$);
			  SYMP->pushNew($$); }
	;

parameter_value_assignmentE:	// IEEE: [ parameter_value_assignment ]
		/* empty */				{ $$ = NULL; }
	|	'#' '(' cellpinList ')'			{ $$ = $3; }
	//			// Parentheses are optional around a single parameter
	|	'#' yaINTNUM				{ $$ = new AstPin($1,1,"",new AstConst($1,*$2)); }
	|	'#' yaFLOATNUM				{ $$ = new AstPin($1,1,"",new AstConst($1,AstConst::Unsized32(),(int)(($2<0)?($2-0.5):($2+0.5)))); }
	|	'#' idClassSel				{ $$ = new AstPin($1,1,"",$2); }
	//			// Not needed in Verilator:
	//			// Side effect of combining *_instantiations
	//			// '#' delay_value	{ UNSUP }
	;

parameter_port_listE:	// IEEE: parameter_port_list + empty == parameter_value_assignment
		/* empty */				{ $$ = NULL; }
	|	'#' '(' ')'				{ $$ = NULL; }
	//			// IEEE: '#' '(' list_of_param_assignments { ',' parameter_port_declaration } ')'
	//			// IEEE: '#' '(' parameter_port_declaration { ',' parameter_port_declaration } ')'
	//			// Can't just do that as "," conflicts with between vars and between stmts, so
	//			// split into pre-comma and post-comma parts
	|	'#' '(' {VARRESET_LIST(GPARAM);} paramPortDeclOrArgList ')'	{ $$ = $4; VARRESET_NONLIST(UNKNOWN); }
	//			// Note legal to start with "a=b" with no parameter statement
	;

paramPortDeclOrArgList:	// IEEE: list_of_param_assignments + { parameter_port_declaration }
		paramPortDeclOrArg				{ $$ = $1; }
	|	paramPortDeclOrArgList ',' paramPortDeclOrArg	{ $$ = $1->addNext($3); }
	;

paramPortDeclOrArg:	// IEEE: param_assignment + parameter_port_declaration
	//			// We combine the two as we can't tell which follows a comma
		param_assignment				{ $$ = $1; }
	|	parameter_port_declarationFront param_assignment	{ $$ = $2; }
	;

portsStarE:		// IEEE: .* + list_of_ports + list_of_port_declarations + empty
		/* empty */					{ $$ = NULL; }
	|	'(' ')'						{ $$ = NULL; }
	//			// .* expanded from module_declaration
	//UNSUP	'(' yP_DOTSTAR ')'				{ UNSUP }
	|	'(' {VARRESET_LIST(PORT);} list_of_ports ')'	{ $$ = $3; VARRESET_NONLIST(UNKNOWN); }
	;

list_of_ports:		// IEEE: list_of_ports + list_of_port_declarations
		port					{ $$ = $1; }
	|	list_of_ports ',' port			{ $$ = $1->addNextNull($3); }
	;

port:			// ==IEEE: port
	//			// Though not type for interfaces, we factor out the port direction and type
	//			// so we can simply handle it in one place
	//
	//			// IEEE: interface_port_header port_identifier { unpacked_dimension }
	//			// Expanded interface_port_header
	//			// We use instantCb here because the non-port form looks just like a module instantiation
	//UNSUP	portDirNetE id/*interface*/                      idAny/*port*/ rangeListE sigAttrListE	{ VARDTYPE($2); VARDONEA($<fl>3, $3, $4); PARSEP->instantCb($<fl>2, $2, $3, $4); PINNUMINC(); }
	//UNSUP	portDirNetE yINTERFACE                           idAny/*port*/ rangeListE sigAttrListE	{ VARDTYPE($2); VARDONEA($<fl>3, $3, $4); PINNUMINC(); }
	//UNSUP	portDirNetE id/*interface*/ '.' idAny/*modport*/ idAny/*port*/ rangeListE sigAttrListE	{ VARDTYPE($2); VARDONEA($<fl>5, $5, $6); PARSEP->instantCb($<fl>2, $2, $5, $6); PINNUMINC(); }
	//UNSUP	portDirNetE yINTERFACE      '.' idAny/*modport*/ idAny/*port*/ rangeListE sigAttrListE	{ VARDTYPE($2); VARDONEA($<fl>5, $5, $6); PINNUMINC(); }
	//
	//			// IEEE: ansi_port_declaration, with [port_direction] removed
	//			//   IEEE: [ net_port_header | interface_port_header ] port_identifier { unpacked_dimension }
	//			//   IEEE: [ net_port_header | variable_port_header ] '.' port_identifier '(' [ expression ] ')'
	//			//   IEEE: [ variable_port_header ] port_identifier { variable_dimension } [ '=' constant_expression ]
	//			//   Substitute net_port_header = [ port_direction ] net_port_type
	//			//   Substitute variable_port_header = [ port_direction ] variable_port_type
	//			//   Substitute net_port_type = [ net_type ] data_type_or_implicit
	//			//   Substitute variable_port_type = var_data_type
	//			//   Substitute var_data_type = data_type | yVAR data_type_or_implicit
	//			//     [ [ port_direction ] net_port_type | interface_port_header            ] port_identifier { unpacked_dimension }
	//			//     [ [ port_direction ] var_data_type                                    ] port_identifier variable_dimensionListE [ '=' constant_expression ]
	//			//     [ [ port_direction ] net_port_type | [ port_direction ] var_data_type ] '.' port_identifier '(' [ expression ] ')'
	//
	//			// Remove optional '[...] id' is in portAssignment
	//			// Remove optional '[port_direction]' is in port
	//			//     net_port_type | interface_port_header            port_identifier { unpacked_dimension }
	//			//     net_port_type | interface_port_header            port_identifier { unpacked_dimension }
	//			//     var_data_type                                    port_identifier variable_dimensionListE [ '=' constExpr ]
	//			//     net_port_type | [ port_direction ] var_data_type '.' port_identifier '(' [ expr ] ')'
	//			// Expand implicit_type
	//
	//			// variable_dimensionListE instead of rangeListE to avoid conflicts
	//
	//			// Note implicit rules looks just line declaring additional followon port
	//			// No VARDECL("port") for implicit, as we don't want to declare variables for them
	//UNSUP	portDirNetE data_type	       '.' portSig '(' portAssignExprE ')' sigAttrListE	{ UNSUP }
	//UNSUP	portDirNetE yVAR data_type     '.' portSig '(' portAssignExprE ')' sigAttrListE	{ UNSUP }
	//UNSUP	portDirNetE yVAR implicit_type '.' portSig '(' portAssignExprE ')' sigAttrListE	{ UNSUP }
	//UNSUP	portDirNetE signingE rangeList '.' portSig '(' portAssignExprE ')' sigAttrListE	{ UNSUP }
	//UNSUP	portDirNetE /*implicit*/       '.' portSig '(' portAssignExprE ')' sigAttrListE	{ UNSUP }
	//
		portDirNetE data_type           portSig variable_dimensionListE sigAttrListE
			{ $$=$3; VARDTYPE($2); $$->addNextNull(VARDONEP($$,$4,$5)); }
	|	portDirNetE yVAR data_type      portSig variable_dimensionListE sigAttrListE
			{ $$=$4; VARDTYPE($3); $$->addNextNull(VARDONEP($$,$5,$6)); }
	|	portDirNetE yVAR implicit_typeE portSig variable_dimensionListE sigAttrListE
			{ $$=$4; VARDTYPE($3); $$->addNextNull(VARDONEP($$,$5,$6)); }
	|	portDirNetE signingE rangeList  portSig variable_dimensionListE sigAttrListE
			{ $$=$4; VARDTYPE(GRAMMARP->addRange(new AstBasicDType($3->fileline(), LOGIC_IMPLICIT, $2), $3,false)); $$->addNextNull(VARDONEP($$,$5,$6)); }
	|	portDirNetE /*implicit*/        portSig variable_dimensionListE sigAttrListE
			{ $$=$2; /*VARDTYPE-same*/ $$->addNextNull(VARDONEP($$,$3,$4)); }
	//
	|	portDirNetE data_type           portSig variable_dimensionListE sigAttrListE '=' constExpr
			{ $$=$3; VARDTYPE($2); AstVar* vp=VARDONEP($$,$4,$5); $$->addNextNull(vp); vp->valuep($7); }
	|	portDirNetE yVAR data_type      portSig variable_dimensionListE sigAttrListE '=' constExpr
			{ $$=$4; VARDTYPE($3); AstVar* vp=VARDONEP($$,$5,$6); $$->addNextNull(vp); vp->valuep($8); }
	|	portDirNetE yVAR implicit_typeE portSig variable_dimensionListE sigAttrListE '=' constExpr
			{ $$=$4; VARDTYPE($3); AstVar* vp=VARDONEP($$,$5,$6); $$->addNextNull(vp); vp->valuep($8); }
	|	portDirNetE /*implicit*/        portSig variable_dimensionListE sigAttrListE '=' constExpr
			{ $$=$2; /*VARDTYPE-same*/ AstVar* vp=VARDONEP($$,$3,$4); $$->addNextNull(vp); vp->valuep($6); }
 	;

portDirNetE:			// IEEE: part of port, optional net type and/or direction
		/* empty */				{ }
	//			// Per spec, if direction given default the nettype.
	//			// The higher level rule may override this VARDTYPE with one later in the parse.
	|	port_direction				{ VARDECL(PORT); VARDTYPE(NULL/*default_nettype*/); }
	|	port_direction net_type			{ VARDECL(PORT); VARDTYPE(NULL/*default_nettype*/); } // net_type calls VARNET
	|	net_type				{ } // net_type calls VARNET
 	;

port_declNetE:			// IEEE: part of port_declaration, optional net type
		/* empty */				{ }
	|	net_type				{ } // net_type calls VARNET
 	;

portSig:
		id/*port*/				{ $$ = new AstPort($<fl>1,PINNUMINC(),*$1); }
	|	idSVKwd					{ $$ = new AstPort($<fl>1,PINNUMINC(),*$1); }
 	;

//**********************************************************************
// Interface headers

//**********************************************************************
// Program headers

program_declaration:		// IEEE: program_declaration + program_nonansi_header + program_ansi_header:
	//			// timeunits_delcarationE is instead in program_item
		pgmFront parameter_port_listE portsStarE ';'
			program_itemListE yENDPROGRAM endLabelE
			{ $1->modTrace(v3Global.opt.trace() && $1->fileline()->tracingOn());  // Stash for implicit wires, etc
			  if ($2) $1->addStmtp($2); if ($3) $1->addStmtp($3);
			  if ($5) $1->addStmtp($5);
			  SYMP->popScope($1);
			  GRAMMARP->endLabel($<fl>7,$1,$7); }
	//UNSUP	yEXTERN	pgmFront parameter_port_listE portsStarE ';'
	//UNSUP		{ PARSEP->symPopScope(VAstType::PROGRAM); }
	;

pgmFront:
		yPROGRAM lifetimeE idAny/*new_program*/
			{ $$ = new AstModule($1,*$3); $$->inLibrary(PARSEP->inLibrary()||PARSEP->inCellDefine());
			  $$->modTrace(v3Global.opt.trace());
			  GRAMMARP->m_modp = $$; GRAMMARP->m_modTypeImpNum = 0;
			  PARSEP->rootp()->addModulep($$);
			  SYMP->pushNew($$); }
	;

program_itemListE:	// ==IEEE: [{ program_item }]
		/* empty */				{ $$ = NULL; }
	|	program_itemList			{ $$ = $1; }
	;

program_itemList:	// ==IEEE: { program_item }
		program_item				{ $$ = $1; }
	|	program_itemList program_item		{ $$ = $1->addNextNull($2); }
	;

program_item:		// ==IEEE: program_item
		port_declaration ';'			{ $$ = $1; }
	|	non_port_program_item			{ $$ = $1; }
	;

non_port_program_item:	// ==IEEE: non_port_program_item
		continuous_assign			{ $$ = $1; }
	|	module_or_generate_item_declaration	{ $$ = $1; }
	|	initial_construct			{ $$ = $1; }
	|	final_construct				{ $$ = $1; }
	|	concurrent_assertion_item		{ $$ = $1; }
	|	timeunits_declaration			{ $$ = $1; }
	|	program_generate_item			{ $$ = $1; }
	;

program_generate_item:		// ==IEEE: program_generate_item
		loop_generate_construct			{ $$ = $1; }
	|	conditional_generate_construct		{ $$ = $1; }
	|	generate_region				{ $$ = $1; }
	;

//************************************************
// Variable Declarations

genvar_declaration:	// ==IEEE: genvar_declaration
		yGENVAR list_of_genvar_identifiers ';'	{ $$ = $2; }
	;

list_of_genvar_identifiers:	// IEEE: list_of_genvar_identifiers (for declaration)
		genvar_identifierDecl			{ $$ = $1; }
	|	list_of_genvar_identifiers ',' genvar_identifierDecl	{ $$ = $1->addNext($3); }
	;

genvar_identifierDecl:		// IEEE: genvar_identifier (for declaration)
		id/*new-genvar_identifier*/ sigAttrListE
			{ VARRESET_NONLIST(GENVAR); VARDTYPE(new AstBasicDType($<fl>1,AstBasicDTypeKwd::INTEGER));
			  $$ = VARDONEA($<fl>1, *$1, NULL, $2); }
	;

local_parameter_declaration:	// IEEE: local_parameter_declaration
	//			// See notes in parameter_declaration
		local_parameter_declarationFront list_of_param_assignments ';'	{ $$ = $2; }
	;

parameter_declaration:	// IEEE: parameter_declaration
	//			// IEEE: yPARAMETER yTYPE list_of_type_assignments ';'
	//			// Instead of list_of_type_assignments
	//			// we use list_of_param_assignments because for port handling
	//			// it already must accept types, so simpler to have code only one place
		parameter_declarationFront list_of_param_assignments	{ $$ = $2; }
	;

local_parameter_declarationFront: // IEEE: local_parameter_declaration w/o assignment
		varLParamReset implicit_typeE 		{ /*VARRESET-in-varLParam*/ VARDTYPE($2); }
	|	varLParamReset data_type		{ /*VARRESET-in-varLParam*/ VARDTYPE($2); }
	//UNSUP	varLParamReset yTYPE			{ /*VARRESET-in-varLParam*/ VARDTYPE($2); }
	;

parameter_declarationFront:	// IEEE: parameter_declaration w/o assignment
		varGParamReset implicit_typeE 		{ /*VARRESET-in-varGParam*/ VARDTYPE($2); }
	|	varGParamReset data_type		{ /*VARRESET-in-varGParam*/ VARDTYPE($2); }
	//UNSUP	varGParamReset yTYPE			{ /*VARRESET-in-varGParam*/ VARDTYPE($2); }
	;

parameter_port_declarationFront: // IEEE: parameter_port_declaration w/o assignment
	//			// IEEE: parameter_declaration (minus assignment)
		parameter_declarationFront		{ }
	//
	//UNSUP	data_type				{ VARDTYPE($1); }
	//UNSUP	yTYPE 					{ VARDTYPE($1); }
	;

net_declaration:		// IEEE: net_declaration - excluding implict
		net_declarationFront netSigList ';'	{ $$ = $2; }
	;

net_declarationFront:		// IEEE: beginning of net_declaration
		net_declRESET net_type   strengthSpecE signingE delayrange { VARDTYPE($5); $5->basicp()->setSignedState($4); }
	;

net_declRESET:
		/* empty */ 				{ VARRESET_NONLIST(UNKNOWN); }
	;

net_type:			// ==IEEE: net_type
		ySUPPLY0				{ VARDECL(SUPPLY0); }
	|	ySUPPLY1				{ VARDECL(SUPPLY1); }
	|	yTRI 					{ VARDECL(TRIWIRE); }
	//UNSUP	yTRI0 					{ VARDECL(TRI0); }
	//UNSUP	yTRI1 					{ VARDECL(TRI1); }
	//UNSUP	yTRIAND 				{ VARDECL(TRIAND); }
	//UNSUP	yTRIOR 					{ VARDECL(TRIOR); }
	//UNSUP	yTRIREG 				{ VARDECL(TRIREG); }
	//UNSUP	yWAND 					{ VARDECL(WAND); }
	|	yWIRE 					{ VARDECL(WIRE); }
	//UNSUP	yWOR 					{ VARDECL(WOR); }
	;

varRESET:
		/* empty */ 				{ VARRESET_NONLIST(VAR); }
	;

varGParamReset:
		yPARAMETER				{ VARRESET_NONLIST(GPARAM); }
	;

varLParamReset:
		yLOCALPARAM				{ VARRESET_NONLIST(LPARAM); }
	;

port_direction:			// ==IEEE: port_direction + tf_port_direction
	//			// IEEE 19.8 just "input" FIRST forces type to wire - we'll ignore that here
		yINPUT					{ VARIO(INPUT); }
	|	yOUTPUT					{ VARIO(OUTPUT); }
	|	yINOUT					{ VARIO(INOUT); }
	//UNSUP	yREF					{ VARIO(REF); }
	//UNSUP	yCONST__REF yREF			{ VARIO(CONSTREF); }
	;

port_directionReset:		// IEEE: port_direction that starts a port_declaraiton
	//			// Used only for declarations outside the port list
		yINPUT					{ VARRESET_NONLIST(UNKNOWN); VARIO(INPUT); }
	|	yOUTPUT					{ VARRESET_NONLIST(UNKNOWN); VARIO(OUTPUT); }
	|	yINOUT					{ VARRESET_NONLIST(UNKNOWN); VARIO(INOUT); }
	//UNSUP	yREF					{ VARRESET_NONLIST(UNKNOWN); VARIO(REF); }
	//UNSUP	yCONST__REF yREF			{ VARRESET_NONLIST(UNKNOWN); VARIO(CONSTREF); }
	;

port_declaration:	// ==IEEE: port_declaration
	//			// Used inside block; followed by ';'
	//			// SIMILAR to tf_port_declaration
	//
	//			// IEEE: inout_declaration
	//			// IEEE: input_declaration
	//			// IEEE: output_declaration
	//			// IEEE: ref_declaration
		port_directionReset port_declNetE data_type          { VARDTYPE($3); }
			list_of_variable_decl_assignments			{ $$ = $5; }
	|	port_directionReset port_declNetE yVAR data_type     { VARDTYPE($4); }
			list_of_variable_decl_assignments			{ $$ = $6; }
	|	port_directionReset port_declNetE yVAR implicit_typeE { VARDTYPE($4); }
			list_of_variable_decl_assignments			{ $$ = $6; }
	|	port_directionReset port_declNetE signingE rangeList { VARDTYPE(GRAMMARP->addRange(new AstBasicDType($4->fileline(), LOGIC_IMPLICIT, $3),$4,false)); }
			list_of_variable_decl_assignments			{ $$ = $6; }
	|	port_directionReset port_declNetE signing	     { VARDTYPE(new AstBasicDType($<fl>3, LOGIC_IMPLICIT, $3)); }
			list_of_variable_decl_assignments			{ $$ = $5; }
	|	port_directionReset port_declNetE /*implicit*/       { VARDTYPE(NULL);/*default_nettype*/}
			list_of_variable_decl_assignments			{ $$ = $4; }
	;

tf_port_declaration:	// ==IEEE: tf_port_declaration
	//			// Used inside function; followed by ';'
	//			// SIMILAR to port_declaration
	//
		port_directionReset      data_type      { VARDTYPE($2); }  list_of_tf_variable_identifiers ';'	{ $$ = $4; }
	|	port_directionReset      implicit_typeE { VARDTYPE($2); }  list_of_tf_variable_identifiers ';'	{ $$ = $4; }
	|	port_directionReset yVAR data_type      { VARDTYPE($3); }  list_of_tf_variable_identifiers ';'	{ $$ = $5; }
	|	port_directionReset yVAR implicit_typeE { VARDTYPE($3); }  list_of_tf_variable_identifiers ';'	{ $$ = $5; }
	;

integer_atom_type:	// ==IEEE: integer_atom_type
		yBYTE					{ $$ = new AstBasicDType($1,AstBasicDTypeKwd::BYTE); }
	|	ySHORTINT				{ $$ = new AstBasicDType($1,AstBasicDTypeKwd::SHORTINT); }
	|	yINT					{ $$ = new AstBasicDType($1,AstBasicDTypeKwd::INT); }
	|	yLONGINT				{ $$ = new AstBasicDType($1,AstBasicDTypeKwd::LONGINT); }
	|	yINTEGER				{ $$ = new AstBasicDType($1,AstBasicDTypeKwd::INTEGER); }
	|	yTIME					{ $$ = new AstBasicDType($1,AstBasicDTypeKwd::TIME); }
	;

integer_vector_type:	// ==IEEE: integer_atom_type
		yBIT					{ $$ = new AstBasicDType($1,AstBasicDTypeKwd::BIT); }
	|	yLOGIC					{ $$ = new AstBasicDType($1,AstBasicDTypeKwd::LOGIC); }
	|	yREG					{ $$ = new AstBasicDType($1,AstBasicDTypeKwd::LOGIC); } // logic==reg
	;

non_integer_type:	// ==IEEE: non_integer_type						     
		yREAL					{ $$ = new AstBasicDType($1,AstBasicDTypeKwd::DOUBLE); }
	|	yREALTIME				{ $$ = new AstBasicDType($1,AstBasicDTypeKwd::DOUBLE); }
	//UNSUP	ySHORTREAL				{ $$ = new AstBasicDType($1,AstBasicDTypeKwd::FLOAT); }
	//			// VAMS - somewhat hackish
	|	yWREAL 					{ $$ = new AstBasicDType($1,AstBasicDTypeKwd::DOUBLE); VARDECL(WIRE); }
	;

signingE:		// IEEE: signing - plus empty
		/*empty*/ 				{ $$ = signedst_NOSIGNED; }
	|	signing					{ $$ = $1; }
	;

signing:		// ==IEEE: signing
		ySIGNED					{ $<fl>$ = $<fl>1; $$ = signedst_SIGNED; }
	|	yUNSIGNED				{ $<fl>$ = $<fl>1; $$ = signedst_UNSIGNED; }
	;

//************************************************
// Data Types

casting_type:		// IEEE: casting_type
		simple_type				{ $$ = $1; }
	//			// IEEE: constant_primary
	//			// In expr:cast this is expanded to just "expr"
	//
	//			// IEEE: signing
	//See where casting_type used
	//^^	ySIGNED					{ $$ = new AstSigned($1,$3); }
	//^^	yUNSIGNED				{ $$ = new AstUnsigned($1,$3); }
	//UNSUP	ySTRING					{ $$ = $1; }
	//UNSUP	yCONST__ETC/*then `*/			{ $$ = $1; }
	;

simple_type:		// ==IEEE: simple_type
	//			// IEEE: integer_type
		integer_atom_type			{ $$ = $1; }
	|	integer_vector_type			{ $$ = $1; }
	|	non_integer_type			{ $$ = $1; }
	//			// IEEE: ps_type_identifier
	//			// IEEE: ps_parameter_identifier (presumably a PARAMETER TYPE)
	|	ps_type					{ $$ = $1; }
	//			// { generate_block_identifer ... } '.'
	//			// Need to determine if generate_block_identifier can be lex-detected
	;

data_type:		// ==IEEE: data_type
	//			// This expansion also replicated elsewhere, IE data_type__AndID
		data_typeNoRef				{ $$ = $1; }
	//			// IEEE: [ class_scope | package_scope ] type_identifier { packed_dimension }
	|	ps_type  packed_dimensionListE		{ $$ = GRAMMARP->createArray($1,$2,true); }
	//UNSUP	class_scope_type packed_dimensionListE	{ UNSUP }
	//			// IEEE: class_type
	//UNSUP	class_typeWithoutId			{ $$ = $1; }
	//			// IEEE: ps_covergroup_identifier
	//			// we put covergroups under ps_type, so can ignore this
	;

data_typeBasic:		// IEEE: part of data_type
		integer_vector_type signingE rangeListE	{ $1->setSignedState($2); $$ = GRAMMARP->addRange($1,$3,true); }
	|	integer_atom_type signingE		{ $1->setSignedState($2); $$ = $1; }
	|	non_integer_type			{ $$ = $1; }
	;

data_typeNoRef:		// ==IEEE: data_type, excluding class_type etc references
		data_typeBasic				{ $$ = $1; }
	//UNSUP	ySTRUCT        packedSigningE '{' struct_union_memberList '}' packed_dimensionListE
	//UNSUP		{ UNSUP }
	//UNSUP	yUNION taggedE packedSigningE '{' struct_union_memberList '}' packed_dimensionListE
	//UNSUP		{ UNSUP }
	|	enumDecl				{ $$ = new AstDefImplicitDType($1->fileline(),"__typeimpenum"+cvtToStr(GRAMMARP->m_modTypeImpNum++),
										       GRAMMARP->m_modp,$1); }
	|	ySTRING					{ $$ = new AstBasicDType($1,AstBasicDTypeKwd::STRING); }
	|	yCHANDLE				{ $$ = new AstBasicDType($1,AstBasicDTypeKwd::CHANDLE); }
	//UNSUP	yEVENT					{ UNSUP }
	//UNSUP	yVIRTUAL__INTERFACE yINTERFACE id/*interface*/	{ UNSUP }
	//UNSUP	yVIRTUAL__anyID                id/*interface*/	{ UNSUP }
	//UNSUP	type_reference				{ UNSUP }
	//			// IEEE: class_scope: see data_type above
	//			// IEEE: class_type: see data_type above
	//			// IEEE: ps_covergroup: see data_type above
	;

list_of_variable_decl_assignments:	// ==IEEE: list_of_variable_decl_assignments
		variable_decl_assignment		{ $$ = $1; }
	|	list_of_variable_decl_assignments ',' variable_decl_assignment	{ $$ = $1->addNextNull($3); }
	;

variable_decl_assignment:	// ==IEEE: variable_decl_assignment
		id variable_dimensionListE sigAttrListE
			{ $$ = VARDONEA($<fl>1,*$1,$2,$3); }
	|	id variable_dimensionListE sigAttrListE '=' variable_declExpr
			{ $$ = VARDONEA($<fl>1,*$1,$2,$3); $$->valuep($5); }
	|	idSVKwd					{ $$ = NULL; }
	//
	//			// IEEE: "dynamic_array_variable_identifier '[' ']' [ '=' dynamic_array_new ]"
	//			// Matches above with variable_dimensionE = "[]"
	//			// IEEE: "class_variable_identifier [ '=' class_new ]"
	//			// variable_dimensionE must be empty
	//			// Pushed into variable_declExpr:dynamic_array_new
	//
	//			// IEEE: "[ covergroup_variable_identifier ] '=' class_new
	//			// Pushed into variable_declExpr:class_new
	//UNSUP	'=' class_new				{ UNSUP }
	;

list_of_tf_variable_identifiers: // ==IEEE: list_of_tf_variable_identifiers
		tf_variable_identifier			{ $$ = $1; }
	|	list_of_tf_variable_identifiers ',' tf_variable_identifier	{ $$ = $1->addNext($3); }
	;

tf_variable_identifier:		// IEEE: part of list_of_tf_variable_identifiers
		id variable_dimensionListE sigAttrListE
			{ $$ = VARDONEA($<fl>1,*$1, $2, $3); }
	|	id variable_dimensionListE sigAttrListE '=' expr
			{ $$ = VARDONEA($<fl>1,*$1, $2, $3);
			  $$->addNext(new AstAssign($4, new AstVarRef($4, *$1, true), $5)); }
	;

variable_declExpr:		// IEEE: part of variable_decl_assignment - rhs of expr
		expr					{ $$ = $1; }
	//UNSUP	dynamic_array_new			{ $$ = $1; }
	//UNSUP	class_new				{ $$ = $1; }
	;

variable_dimensionListE:	// IEEE: variable_dimension + empty
		/*empty*/				{ $$ = NULL; }
	|	variable_dimensionList			{ $$ = $1; }
	;

variable_dimensionList:	// IEEE: variable_dimension + empty
		variable_dimension			{ $$ = $1; }
	|	variable_dimensionList variable_dimension	{ $$ = $1->addNext($2)->castRange(); }
	;

variable_dimension:	// ==IEEE: variable_dimension
	//			// IEEE: unsized_dimension
	//UNSUP	'[' ']'					{ UNSUP }
	//			// IEEE: unpacked_dimension
		anyrange				{ $$ = $1; }
	|	'[' constExpr ']'			{ $$ = new AstRange($1,new AstSub($1,$2, new AstConst($1,1)), new AstConst($1,0)); }
	//			// IEEE: associative_dimension
	//UNSUP	'[' data_type ']'			{ UNSUP }
	//UNSUP	yP_BRASTAR ']'				{ UNSUP }
	//UNSUP	'[' '*' ']'				{ UNSUP }
	//			// IEEE: queue_dimension
	//			// '[' '$' ']' -- $ is part of expr
	//			// '[' '$' ':' expr ']' -- anyrange:expr:$
	;

//************************************************
// enum

// IEEE: part of data_type
enumDecl:
		yENUM enum_base_typeE '{' enum_nameList '}' { $$ = new AstEnumDType($1,$2,$4); }
	;

enum_base_typeE:	// IEEE: enum_base_type
		/* empty */				{ $$ = new AstBasicDType(CRELINE(),AstBasicDTypeKwd::INT); }
	//			// Not in spec, but obviously "enum [1:0]" should work
	//			// implicit_type expanded, without empty
	|	signingE rangeList			{ $$ = GRAMMARP->addRange(new AstBasicDType($2->fileline(), LOGIC_IMPLICIT, $1),$2,false); }
	|	signing					{ $$ = new AstBasicDType($<fl>1, LOGIC_IMPLICIT, $1); }
	//
	|	integer_atom_type signingE		{ $1->setSignedState($2); $$ = $1; }
	|	integer_vector_type signingE rangeListE	{ $1->setSignedState($2); $$ = GRAMMARP->addRange($1,$3,false); }
	//			// below can be idAny or yaID__aTYPE
	//			// IEEE requires a type, though no shift conflict if idAny
	|	idAny rangeListE			{ $$ = GRAMMARP->createArray(new AstRefDType($<fl>1, *$1), $2, false); }
	;

enum_nameList:
		enum_name_declaration			{ $$ = $1; }
	|	enum_nameList ',' enum_name_declaration	{ $$ = $1->addNextNull($3); }
	;

enum_name_declaration:	// ==IEEE: enum_name_declaration
		idAny/*enum_identifier*/ enumNameRangeE enumNameStartE	{ $$ = new AstEnumItem($<fl>1, *$1, $2, $3); }
	;

enumNameRangeE:		// IEEE: second part of enum_name_declaration
		/* empty */				{ $$ = NULL; }
	|	'[' intnumAsConst ']'			{ $$ = new AstRange($1,new AstConst($1,0), $2); }
	|	'[' intnumAsConst ':' intnumAsConst ']'	{ $$ = new AstRange($1,$2,$4); }
	;

enumNameStartE:		// IEEE: third part of enum_name_declaration
		/* empty */				{ $$ = NULL; }
	|	'=' constExpr				{ $$ = $2; }
	;

intnumAsConst:
		yaINTNUM				{ $$ = new AstConst($<fl>1,*$1); }
	;

//************************************************
// Typedef

data_declaration:	// ==IEEE: data_declaration
	//			// VARRESET can't be called here - conflicts
		data_declarationVar			{ $$ = $1; }
	|	type_declaration			{ $$ = $1; }
	|	package_import_declaration		{ $$ = $1; }
	//			// IEEE: virtual_interface_declaration
	//			// "yVIRTUAL yID yID" looks just like a data_declaration
	//			// Therefore the virtual_interface_declaration term isn't used
	;

data_declarationVar:	// IEEE: part of data_declaration
	//			// The first declaration has complications between assuming what's the type vs ID declaring
		varRESET data_declarationVarFront list_of_variable_decl_assignments ';'	{ $$ = $3; }
	;

data_declarationVarFront:	// IEEE: part of data_declaration
	//			// Expanded: "constE yVAR lifetimeE data_type"
	//			// implicit_type expanded into /*empty*/ or "signingE rangeList"
		/**/ 	    yVAR lifetimeE data_type	{ /*VARRESET-in-ddVar*/ VARDTYPE($3); }
	|	/**/ 	    yVAR lifetimeE		{ /*VARRESET-in-ddVar*/ VARDTYPE(new AstBasicDType($<fl>1, LOGIC_IMPLICIT)); }
	|	/**/ 	    yVAR lifetimeE signingE rangeList { /*VARRESET-in-ddVar*/ VARDTYPE(GRAMMARP->addRange(new AstBasicDType($<fl>1, LOGIC_IMPLICIT, $3), $4,false)); }
	//
	//			// implicit_type expanded into /*empty*/ or "signingE rangeList"
	|	yCONST__ETC yVAR lifetimeE data_type	{ /*VARRESET-in-ddVar*/ VARDTYPE(new AstConstDType($<fl>1, $4)); }
	|	yCONST__ETC yVAR lifetimeE		{ /*VARRESET-in-ddVar*/ VARDTYPE(new AstConstDType($<fl>1, new AstBasicDType($<fl>2, LOGIC_IMPLICIT))); }
 	|	yCONST__ETC yVAR lifetimeE signingE rangeList { /*VARRESET-in-ddVar*/ VARDTYPE(new AstConstDType($<fl>1, GRAMMARP->addRange(new AstBasicDType($<fl>2, LOGIC_IMPLICIT, $4), $5,false))); }
	//
	//			// Expanded: "constE lifetimeE data_type"
	|	/**/		      data_type		{ /*VARRESET-in-ddVar*/ VARDTYPE($1); }
	|	/**/	    lifetime  data_type		{ /*VARRESET-in-ddVar*/ VARDTYPE($2); }
	|	yCONST__ETC lifetimeE data_type		{ /*VARRESET-in-ddVar*/ VARDTYPE(new AstConstDType($<fl>1, $3)); }
	//			// = class_new is in variable_decl_assignment
	;

implicit_typeE:		// IEEE: part of *data_type_or_implicit
	//			// Also expanded in data_declaration
		/* empty */				{ $$ = NULL; }
	|	signingE rangeList			{ $$ = GRAMMARP->addRange(new AstBasicDType($2->fileline(), LOGIC_IMPLICIT, $1),$2,false); }
	|	signing					{ $$ = new AstBasicDType($<fl>1, LOGIC_IMPLICIT, $1); }
	;

type_declaration:	// ==IEEE: type_declaration
	//			// Use idAny, as we can redeclare a typedef on an existing typedef
		yTYPEDEF data_type idAny variable_dimensionListE ';'	{ $$ = new AstTypedef($<fl>1, *$3, GRAMMARP->createArray($2,$4,false)); SYMP->reinsert($$); }
	//UNSUP	yTYPEDEF id/*interface*/ '.' idAny/*type*/ idAny/*type*/ ';'	{ $$ = NULL; $1->v3error("Unsupported: SystemVerilog 2005 typedef in this context"); } //UNSUP
	//			// Combines into above "data_type id" rule
	//			// Verilator: Not important what it is in the AST, just need to make sure the yaID__aTYPE gets returned
	|	yTYPEDEF id ';'				{ $$ = NULL; $$ = new AstTypedefFwd($<fl>1, *$2); SYMP->reinsert($$); }
	|	yTYPEDEF yENUM idAny ';'		{ $$ = NULL; $$ = new AstTypedefFwd($<fl>1, *$3); SYMP->reinsert($$); }
	//UNSUP	yTYPEDEF ySTRUCT idAny ';'		{ $$ = NULL; $$ = new AstTypedefFwd($<fl>1, *$3); SYMP->reinsert($$); }
	//UNSUP	yTYPEDEF yUNION idAny ';'		{ $$ = NULL; $$ = new AstTypedefFwd($<fl>1, *$3); SYMP->reinsert($$); }
	//UNSUP	yTYPEDEF yCLASS idAny ';'		{ $$ = NULL; $$ = new AstTypedefFwd($<fl>1, *$3); SYMP->reinsert($$); }
	;

//************************************************
// Module Items

module_itemListE:	// IEEE: Part of module_declaration
		/* empty */				{ $$ = NULL; }
	|	module_itemList				{ $$ = $1; }
	;

module_itemList:		// IEEE: Part of module_declaration
		module_item				{ $$ = $1; }
	|	module_itemList module_item		{ $$ = $1->addNextNull($2); }
	;

module_item:		// ==IEEE: module_item
		port_declaration ';'			{ $$ = $1; }
	|	non_port_module_item			{ $$ = $1; }
	;

non_port_module_item:	// ==IEEE: non_port_module_item
		generate_region				{ $$ = $1; }
	|	module_or_generate_item 		{ $$ = $1; }
	|	specify_block 				{ $$ = $1; }
	|	specparam_declaration			{ $$ = $1; }
	//UNSUP	program_declaration			{ $$ = $1; }
	//UNSUP	module_declaration			{ $$ = $1; }
	//UNSUP	interface_declaration			{ $$ = $1; }
	|	timeunits_declaration			{ $$ = $1; }
	//			// Verilator specific
	|	yaSCHDR					{ $$ = new AstScHdr($<fl>1,*$1); }
	|	yaSCINT					{ $$ = new AstScInt($<fl>1,*$1); }
	|	yaSCIMP					{ $$ = new AstScImp($<fl>1,*$1); }
	|	yaSCIMPH				{ $$ = new AstScImpHdr($<fl>1,*$1); }
	|	yaSCCTOR				{ $$ = new AstScCtor($<fl>1,*$1); }
	|	yaSCDTOR				{ $$ = new AstScDtor($<fl>1,*$1); }
	|	yVL_INLINE_MODULE			{ $$ = new AstPragma($1,AstPragmaType::INLINE_MODULE); }
	|	yVL_NO_INLINE_MODULE			{ $$ = new AstPragma($1,AstPragmaType::NO_INLINE_MODULE); }
	|	yVL_PUBLIC_MODULE			{ $$ = new AstPragma($1,AstPragmaType::PUBLIC_MODULE); }
	;

generate_region:		// ==IEEE: generate_region
		yGENERATE genTopBlock yENDGENERATE	{ $$ = new AstGenerate($1, $2); }
	|	yGENERATE yENDGENERATE			{ $$ = NULL; }
	;

module_or_generate_item:	// ==IEEE: module_or_generate_item
	//			// IEEE: parameter_override
		yDEFPARAM list_of_defparam_assignments ';'	{ $$ = $2; }
	//			// IEEE: gate_instantiation + udp_instantiation + module_instantiation
	//			// not here, see etcInst in module_common_item
	//			// We joined udp & module definitions, so this goes here
	|	table					{ $$ = $1; }
	|	module_common_item			{ $$ = $1; }
	;

module_common_item:	// ==IEEE: module_common_item
		module_or_generate_item_declaration	{ $$ = $1; }
	//			// IEEE: interface_instantiation
	//			// + IEEE: program_instantiation
	//			// + module_instantiation from module_or_generate_item
	|	etcInst 				{ $$ = $1; }
	|	concurrent_assertion_item		{ $$ = $1; }
	//UNSUP	bind_directive				{ $$ = $1; }
	|	continuous_assign			{ $$ = $1; }
	//			// IEEE: net_alias
	//UNSUP	yALIAS variable_lvalue aliasEqList ';'	{ UNSUP }
	|	initial_construct			{ $$ = $1; }
	|	final_construct				{ $$ = $1; }
	//			// IEEE: always_construct
	//			// Verilator only - event_control attached to always
	|	yALWAYS event_controlE stmtBlock	{ $$ = new AstAlways($1,$2,$3); }
	|	loop_generate_construct			{ $$ = $1; }
	|	conditional_generate_construct		{ $$ = $1; }
	//			// Verilator only
	|	pslStmt 				{ $$ = $1; }
	//
	|	error ';'				{ $$ = NULL; }
	;

continuous_assign:	// IEEE: continuous_assign
		yASSIGN delayE assignList ';'		{ $$ = $3; }
	//UNSUP: strengthSpecE not in above assign
	;

initial_construct:	// IEEE: initial_construct
		yINITIAL stmtBlock			{ $$ = new AstInitial($1,$2); }
	;

final_construct:		// IEEE: final_construct
		yFINAL stmtBlock			{ $$ = new AstFinal($1,$2); }
	;

module_or_generate_item_declaration:	// ==IEEE: module_or_generate_item_declaration
		package_or_generate_item_declaration	{ $$ = $1; }
	| 	genvar_declaration			{ $$ = $1; }
	|	clocking_declaration			{ $$ = $1; }
	//UNSUP	yDEFAULT yCLOCKING idAny/*new-clocking_identifier*/ ';'	{ $$ = $1; }
	;

//************************************************
// Generates

generate_block_or_null:	// IEEE: generate_block_or_null
	//	';'		// is included in
	//			// IEEE: generate_block
		genItem					{ $$ = $1 ? (new AstBegin($1->fileline(),"genblk",$1)) : NULL; }
	|	genItemBegin				{ $$ = $1; }
	;

genTopBlock:
		genItemList				{ $$ = $1; }
	|	genItemBegin				{ $$ = $1; }
	;

genItemBegin:		// IEEE: part of generate_block
		yBEGIN genItemList yEND			{ $$ = new AstBegin($1,"genblk",$2); }
	|	yBEGIN yEND				{ $$ = NULL; }
	|	id ':' yBEGIN genItemList yEND endLabelE	{ $$ = new AstBegin($2,*$1,$4); GRAMMARP->endLabel($<fl>6,*$1,$6); }
	|	id ':' yBEGIN             yEND endLabelE	{ $$ = NULL; GRAMMARP->endLabel($<fl>5,*$1,$5); }
	|	yBEGIN ':' idAny genItemList yEND endLabelE	{ $$ = new AstBegin($2,*$3,$4); GRAMMARP->endLabel($<fl>6,*$3,$6); }
	|	yBEGIN ':' idAny 	  yEND endLabelE	{ $$ = NULL; GRAMMARP->endLabel($<fl>5,*$3,$5); }
	;

genItemList:
		genItem					{ $$ = $1; }
	|	genItemList genItem			{ $$ = $1->addNextNull($2); }
	;

genItem:			// IEEE: module_or_interface_or_generate_item
		module_or_generate_item			{ $$ = $1; }
	//UNSUP	interface_or_generate_item		{ $$ = $1; }
	;

conditional_generate_construct:	// ==IEEE: conditional_generate_construct
		yCASE  '(' expr ')' case_generate_itemListE yENDCASE	{ $$ = new AstGenCase($1,$3,$5); }
	|	yIF '(' expr ')' generate_block_or_null	%prec prLOWER_THAN_ELSE	{ $$ = new AstGenIf($1,$3,$5,NULL); }
	|	yIF '(' expr ')' generate_block_or_null yELSE generate_block_or_null	{ $$ = new AstGenIf($1,$3,$5,$7); }
	;

loop_generate_construct:	// ==IEEE: loop_generate_construct
		yFOR '(' genvar_initialization ';' expr ';' genvar_iteration ')' generate_block_or_null
			{ AstBegin* blkp = new AstBegin($1,"",NULL);  blkp->hidden(true);
			  AstNode* initp = $3;  AstNode* varp = $3;
			  if (varp->castVar()) {  // Genvar
				initp = varp->nextp();
				initp->unlinkFrBackWithNext();  // Detach 2nd from varp, make 1st init
				blkp->addStmtsp(varp);
			  }
			  // Statements are under 'flatsp' so that cells under this
			  // for loop won't get an extra layer of hierarchy tacked on
			  blkp->addFlatsp(new AstGenFor($1,initp,$5,$7,$9));
			  $$ = blkp; }
	;

genvar_initialization:	// ==IEEE: genvar_initalization
		varRefBase '=' expr			{ $$ = new AstAssign($2,$1,$3); }
	|	yGENVAR genvar_identifierDecl '=' constExpr	{ $$ = $2; $2->addNext(new AstAssign($3,new AstVarRef($3,$2,true), $4)); }
	;

genvar_iteration:	// ==IEEE: genvar_iteration
		varRefBase '=' 		expr		{ $$ = new AstAssign($2,$1,$3); }
	|	varRefBase yP_PLUSEQ	expr		{ $$ = new AstAssign($2,$1,new AstAdd    ($2,$1->cloneTree(true),$3)); }
	|	varRefBase yP_MINUSEQ	expr		{ $$ = new AstAssign($2,$1,new AstSub    ($2,$1->cloneTree(true),$3)); }
	|	varRefBase yP_TIMESEQ	expr		{ $$ = new AstAssign($2,$1,new AstMul    ($2,$1->cloneTree(true),$3)); }
	|	varRefBase yP_DIVEQ	expr		{ $$ = new AstAssign($2,$1,new AstDiv    ($2,$1->cloneTree(true),$3)); }
	|	varRefBase yP_MODEQ	expr		{ $$ = new AstAssign($2,$1,new AstModDiv ($2,$1->cloneTree(true),$3)); }
	|	varRefBase yP_ANDEQ	expr		{ $$ = new AstAssign($2,$1,new AstAnd    ($2,$1->cloneTree(true),$3)); }
	|	varRefBase yP_OREQ	expr		{ $$ = new AstAssign($2,$1,new AstOr     ($2,$1->cloneTree(true),$3)); }
	|	varRefBase yP_XOREQ	expr		{ $$ = new AstAssign($2,$1,new AstXor    ($2,$1->cloneTree(true),$3)); }
	|	varRefBase yP_SLEFTEQ	expr		{ $$ = new AstAssign($2,$1,new AstShiftL ($2,$1->cloneTree(true),$3)); }
	|	varRefBase yP_SRIGHTEQ	expr		{ $$ = new AstAssign($2,$1,new AstShiftR ($2,$1->cloneTree(true),$3)); }
	|	varRefBase yP_SSRIGHTEQ	expr		{ $$ = new AstAssign($2,$1,new AstShiftRS($2,$1->cloneTree(true),$3)); }
	//			// inc_or_dec_operator
	// When support ++ as a real AST type, maybe AstWhile::precondsp() becomes generic AstMathStmt?
	|	yP_PLUSPLUS   varRefBase		{ $$ = new AstAssign($1,$2,new AstAdd    ($1,$2->cloneTree(true),new AstConst($1,V3Number($1,"'b1")))); }
	|	yP_MINUSMINUS varRefBase		{ $$ = new AstAssign($1,$2,new AstSub    ($1,$2->cloneTree(true),new AstConst($1,V3Number($1,"'b1")))); }
	|	varRefBase yP_PLUSPLUS			{ $$ = new AstAssign($2,$1,new AstAdd    ($2,$1->cloneTree(true),new AstConst($2,V3Number($2,"'b1")))); }
	|	varRefBase yP_MINUSMINUS		{ $$ = new AstAssign($2,$1,new AstSub    ($2,$1->cloneTree(true),new AstConst($2,V3Number($2,"'b1")))); }
	;

case_generate_itemListE:	// IEEE: [{ case_generate_itemList }]
		/* empty */				{ $$ = NULL; }
	|	case_generate_itemList			{ $$ = $1; }
	;

case_generate_itemList:	// IEEE: { case_generate_itemList }
		case_generate_item			{ $$=$1; }
	|	case_generate_itemList case_generate_item	{ $$=$1; $1->addNext($2); }
	;

case_generate_item:	// ==IEEE: case_generate_item
		caseCondList ':' generate_block_or_null		{ $$ = new AstCaseItem($2,$1,$3); }
	|	yDEFAULT ':' generate_block_or_null		{ $$ = new AstCaseItem($2,NULL,$3); }
	|	yDEFAULT generate_block_or_null			{ $$ = new AstCaseItem($1,NULL,$2); }
	;

//************************************************
// Assignments and register declarations

assignList:
		assignOne				{ $$ = $1; }
	|	assignList ',' assignOne		{ $$ = $1->addNext($3); }
	;

assignOne:
		variable_lvalue '=' expr		{ $$ = new AstAssignW($2,$1,$3); }
	;

delayE:
		/* empty */				{ }
	|	delay_control				{ $1->v3warn(ASSIGNDLY,"Unsupported: Ignoring delay on this assignment/primitive."); } /* ignored */
	;

delay_control:	//== IEEE: delay_control
		'#' delay_value				{ $$ = $1; } /* ignored */
	|	'#' '(' minTypMax ')'			{ $$ = $1; } /* ignored */
	|	'#' '(' minTypMax ',' minTypMax ')'			{ $$ = $1; } /* ignored */
	|	'#' '(' minTypMax ',' minTypMax ',' minTypMax ')'	{ $$ = $1; } /* ignored */
	;

delay_value:			// ==IEEE:delay_value
	//			// IEEE: ps_identifier
		ps_id_etc				{ }
	|	yaINTNUM 				{ }
	|	yaFLOATNUM 				{ }
	|	yaTIMENUM 				{ }
	;

delayExpr:
		expr					{ }
	//			// Verilator doesn't support yaTIMENUM, so not in expr
	|	yaTIMENUM 				{ }
	;

minTypMax:			// IEEE: mintypmax_expression and constant_mintypmax_expression
		delayExpr				{ }
	|	delayExpr ':' delayExpr ':' delayExpr	{ }
	;

netSigList:		// IEEE: list_of_port_identifiers
		netSig  				{ $$ = $1; }
	|	netSigList ',' netSig		       	{ $$ = $1; $1->addNext($3); }
	;

netSig:			// IEEE: net_decl_assignment -  one element from list_of_port_identifiers
		netId sigAttrListE			{ $$ = VARDONEA($<fl>1,*$1, NULL, $2); }
	|	netId sigAttrListE '=' expr		{ $$ = VARDONEA($<fl>1,*$1, NULL, $2); $$->addNext(new AstAssignW($3,new AstVarRef($3,$$->name(),true),$4)); }
	|	netId rangeList sigAttrListE		{ $$ = VARDONEA($<fl>1,*$1, $2, $3); }
	;

netId:
		id/*new-net*/				{ $$ = $1; $<fl>$=$<fl>1; }
	|	idSVKwd					{ $$ = $1; $<fl>$=$<fl>1; }
	;

sigId:
		id					{ $$ = VARDONEA($<fl>1,*$1, NULL, NULL); }
	;

sigAttrListE:
		/* empty */				{ $$ = NULL; }
	|	sigAttrList				{ $$ = $1; }
	;

sigAttrList:
		sigAttr					{ $$ = $1; }
	|	sigAttrList sigAttr			{ $$ = $1->addNextNull($2); }
	;

sigAttr:
		yVL_CLOCK				{ $$ = new AstAttrOf($1,AstAttrType::VAR_CLOCK); }
	|	yVL_CLOCK_ENABLE			{ $$ = new AstAttrOf($1,AstAttrType::VAR_CLOCK_ENABLE); }
	|	yVL_PUBLIC				{ $$ = new AstAttrOf($1,AstAttrType::VAR_PUBLIC); }
	|	yVL_PUBLIC_FLAT				{ $$ = new AstAttrOf($1,AstAttrType::VAR_PUBLIC_FLAT); }
	|	yVL_PUBLIC_FLAT_RD			{ $$ = new AstAttrOf($1,AstAttrType::VAR_PUBLIC_FLAT_RD); }
	|	yVL_PUBLIC_FLAT_RW			{ $$ = new AstAttrOf($1,AstAttrType::VAR_PUBLIC_FLAT_RW); }
	|	yVL_PUBLIC_FLAT_RW attr_event_control	{ $$ = new AstAttrOf($1,AstAttrType::VAR_PUBLIC_FLAT_RW);
							  $$ = $$->addNext(new AstAlwaysPublic($1,$2,NULL)); }
	|	yVL_ISOLATE_ASSIGNMENTS			{ $$ = new AstAttrOf($1,AstAttrType::VAR_ISOLATE_ASSIGNMENTS); }
	|	yVL_SC_BV				{ $$ = new AstAttrOf($1,AstAttrType::VAR_SC_BV); }
	|	yVL_SFORMAT				{ $$ = new AstAttrOf($1,AstAttrType::VAR_SFORMAT); }
	;

rangeListE:		// IEEE: [{packed_dimension}]
		/* empty */    		               	{ $$ = NULL; }
	|	rangeList 				{ $$ = $1; }
	;

rangeList:		// IEEE: {packed_dimension}
		anyrange				{ $$ = $1; }
        |	rangeList anyrange			{ $$ = $1; $1->addNext($2); }
	;

wirerangeE:
		/* empty */    		               	{ $$ = new AstBasicDType(CRELINE(), LOGIC); }  // not implicit
	|	rangeList 				{ $$ = GRAMMARP->addRange(new AstBasicDType($1->fileline(), LOGIC),$1,false); }  // not implicit
	;

// IEEE: select
// Merged into more general idArray

anyrange:
		'[' constExpr ':' constExpr ']'		{ $$ = new AstRange($1,$2,$4); }
	;

packed_dimensionListE:	// IEEE: [{ packed_dimension }]
		/* empty */				{ $$ = NULL; }
	|	packed_dimensionList			{ $$ = $1; }
	;

packed_dimensionList:	// IEEE: { packed_dimension }
		packed_dimension			{ $$ = $1; }
	|	packed_dimensionList packed_dimension	{ $$ = $1->addNext($2)->castRange(); }
	;

packed_dimension:	// ==IEEE: packed_dimension
		anyrange				{ $$ = $1; }
	//UNSUP	'[' ']'					{ UNSUP }
	;

delayrange:
		wirerangeE delayE 			{ $$ = $1; }
	|	ySCALARED wirerangeE delayE 		{ $$ = $2; }
	|	yVECTORED wirerangeE delayE 		{ $$ = $2; }
	//UNSUP: ySCALARED/yVECTORED ignored
	;

//************************************************
// Parameters

param_assignment:		// ==IEEE: param_assignment
	//			// IEEE: constant_param_expression
	//			// constant_param_expression: '$' is in expr
		sigId sigAttrListE '=' expr		{ $$ = $1; $1->addAttrsp($2); $$->valuep($4); }
	//UNSUP:  exprOrDataType instead of expr
	;

list_of_param_assignments:	// ==IEEE: list_of_param_assignments
		param_assignment			{ $$ = $1; }
	|	list_of_param_assignments ',' param_assignment	{ $$ = $1; $1->addNext($3); }
	;

list_of_defparam_assignments:	//== IEEE: list_of_defparam_assignments
		defparam_assignment			{ $$ = $1; }
	|	list_of_defparam_assignments ',' defparam_assignment	{ $$ = $1->addNext($3); }
	;

defparam_assignment:	// ==IEEE: defparam_assignment
		id '.' id '=' expr 			{ $$ = new AstDefParam($4,*$1,*$3,$5); }
	//UNSUP	More general dotted identifiers
	;

//************************************************
// Instances
// We don't know identifier types, so this matches all module,udp,etc instantiation
//   module_id      [#(params)]   name  (pins) [, name ...] ;	// module_instantiation
//   gate (strong0) [#(delay)]   [name] (pins) [, (pins)...] ;	// gate_instantiation
//   program_id     [#(params}]   name ;			// program_instantiation
//   interface_id   [#(params}]   name ;			// interface_instantiation

etcInst:			// IEEE: module_instantiation + gate_instantiation + udp_instantiation
		instDecl				{ $$ = $1; }
	|	gateDecl 				{ $$ = $1; }
	;

instDecl:
		id parameter_value_assignmentE {INSTPREP(*$1,$2);} instnameList ';'
			{ $$ = $4; GRAMMARP->m_impliedDecl=false;}
	//UNSUP: strengthSpecE for udp_instantiations
	;

instnameList:
		instnameParen				{ $$ = $1; }
	|	instnameList ',' instnameParen		{ $$ = $1->addNext($3); }
	;

instnameParen:
		id instRangeE '(' cellpinList ')'	{ $$ = new AstCell($<fl>1,*$1,GRAMMARP->m_instModule,$4,  GRAMMARP->m_instParamp,$2); }
	|	id instRangeE 				{ $$ = new AstCell($<fl>1,*$1,GRAMMARP->m_instModule,NULL,GRAMMARP->m_instParamp,$2); }
	//UNSUP	instRangeE '(' cellpinList ')'		{ UNSUP } // UDP
	;

instRangeE:
		/* empty */				{ $$ = NULL; }
	|	'[' constExpr ']'			{ $$ = new AstRange($1,$2,$2->cloneTree(true)); }
	|	'[' constExpr ':' constExpr ']'		{ $$ = new AstRange($1,$2,$4); }
	;

cellpinList:
		{VARRESET_LIST(UNKNOWN);} cellpinItList	{ $$ = $2; VARRESET_NONLIST(UNKNOWN); }
	;

cellpinItList:		// IEEE: list_of_port_connections + list_of_parameter_assignmente
		cellpinItemE				{ $$ = $1; }
	|	cellpinItList ',' cellpinItemE		{ $$ = $1->addNextNull($3)->castPin(); }
	;

cellpinItemE:		// IEEE: named_port_connection + named_parameter_assignment + empty
				// Note empty can match either () or (,); V3LinkCells cleans up ()
		/* empty: ',,' is legal */		{ $$ = new AstPin(CRELINE(),PINNUMINC(),"",NULL); }
	|	yP_DOTSTAR				{ $$ = new AstPin($1,PINNUMINC(),".*",NULL); }
	|	'.' idSVKwd				{ $$ = new AstPin($1,PINNUMINC(),*$2,new AstVarRef($1,*$2,false)); $$->svImplicit(true);}
	|	'.' idAny				{ $$ = new AstPin($1,PINNUMINC(),*$2,new AstVarRef($1,*$2,false)); $$->svImplicit(true);}
	|	'.' idAny '(' ')'			{ $$ = new AstPin($1,PINNUMINC(),*$2,NULL); }
	//			// mintypmax is expanded here, as it might be a UDP or gate primitive
	|	'.' idAny '(' expr ')'			{ $$ = new AstPin($1,PINNUMINC(),*$2,$4); }
	//UNSUP	'.' idAny '(' expr ':' expr ')'		{ }
	//UNSUP	'.' idAny '(' expr ':' expr ':' expr ')' { }
	//			// For parameters
	//UNSUP	'.' idAny '(' data_type ')'		{ PINDONE($1,$2,$4);  GRAMMARP->pinNumInc(); }
	//			// For parameters
	//UNSUP	data_type				{ PINDONE($1->fileline(),"",$1);  GRAMMARP->pinNumInc(); }
	//
	|	expr					{ $$ = new AstPin($1->fileline(),PINNUMINC(),"",$1); }
	//UNSUP	expr ':' expr				{ }
	//UNSUP	expr ':' expr ':' expr			{ }
	;

//************************************************
// EventControl lists

attr_event_control:	// ==IEEE: event_control
		'@' '(' event_expression ')'		{ $$ = new AstSenTree($1,$3); }
	|	'@' '(' '*' ')'				{ $$ = NULL; }
	|	'@' '*'					{ $$ = NULL; }
	;

event_controlE:
		/* empty */				{ $$ = NULL; }
	|	event_control				{ $$ = $1; }
	;

event_control:	// ==IEEE: event_control
		'@' '(' event_expression ')'		{ $$ = new AstSenTree($1,$3); }
	|	'@' '(' '*' ')'				{ $$ = NULL; }
	|	'@' '*'					{ $$ = NULL; }
	//			// IEEE: hierarchical_event_identifier
	|	'@' senitemVar				{ $$ = new AstSenTree($1,$2); }	/* For events only */
	//			// IEEE: sequence_instance
	//			// sequence_instance without parens matches idClassSel above.
	//			// Ambiguity: "'@' sequence (-for-sequence" versus expr:delay_or_event_controlE "'@' id (-for-expr
	//			// For now we avoid this, as it's very unlikely someone would mix
	//			// 1995 delay with a sequence with parameters.
	//			// Alternatively split this out of event_control, and delay_or_event_controlE
	//			// and anywhere delay_or_event_controlE is called allow two expressions
	//|	'@' idClassSel '(' list_of_argumentsE ')'	{ }
	;

event_expression:	// IEEE: event_expression - split over several
		senitem					{ $$ = $1; }
	|	event_expression yOR senitem		{ $$ = $1;$1->addNextNull($3); }
	|	event_expression ',' senitem		{ $$ = $1;$1->addNextNull($3); }	/* Verilog 2001 */
	;

senitem:		// IEEE: part of event_expression, non-'OR' ',' terms
		senitemEdge				{ $$ = $1; }
	|	senitemVar				{ $$ = $1; }
	|	'(' senitemVar ')'			{ $$ = $2; }
	//UNSUP	expr					{ UNSUP }
	//UNSUP	expr yIFF expr				{ UNSUP }
	// Since expr is unsupported we allow and ignore constants (removed in V3Const)
	|	yaINTNUM				{ $$ = NULL; }
	|	yaFLOATNUM				{ $$ = NULL; }
	|	'(' yaINTNUM ')'			{ $$ = NULL; }
	|	'(' yaFLOATNUM ')'			{ $$ = NULL; }
	;

senitemVar:
		idClassSel				{ $$ = new AstSenItem($1->fileline(),AstEdgeType::ET_ANYEDGE,$1); }
	;

senitemEdge:		// IEEE: part of event_expression
		yPOSEDGE idClassSel			{ $$ = new AstSenItem($1,AstEdgeType::ET_POSEDGE,$2); }
	|	yNEGEDGE idClassSel			{ $$ = new AstSenItem($1,AstEdgeType::ET_NEGEDGE,$2); }
	|	yEDGE idClassSel			{ $$ = new AstSenItem($1,AstEdgeType::ET_BOTHEDGE,$2); }
	|	yPOSEDGE '(' idClassSel ')'		{ $$ = new AstSenItem($1,AstEdgeType::ET_POSEDGE,$3); }
	|	yNEGEDGE '(' idClassSel ')'		{ $$ = new AstSenItem($1,AstEdgeType::ET_NEGEDGE,$3); }
	|	yEDGE '(' idClassSel ')'		{ $$ = new AstSenItem($1,AstEdgeType::ET_BOTHEDGE,$3); }
	//UNSUP	yIFF...
	;

//************************************************
// Statements

stmtBlock:		// IEEE: statement + seq_block + par_block
		stmt					{ $$ = $1; }
	;

seq_block:		// ==IEEE: seq_block
	//			// IEEE doesn't allow declarations in unnamed blocks, but several simulators do.
	//			// So need begin's even if unnamed to scope variables down
		seq_blockFront blockDeclStmtList yEND endLabelE	{ $$=$1; $1->addStmtsp($2); SYMP->popScope($1); GRAMMARP->endLabel($<fl>4,$1,$4); }
	|	seq_blockFront /**/		 yEND endLabelE	{ $$=$1; SYMP->popScope($1); GRAMMARP->endLabel($<fl>3,$1,$3); }
	;

seq_blockFront:		// IEEE: part of par_block
		yBEGIN					 { $$ = new AstBegin($1,"",NULL);  SYMP->pushNew($$); }
	|	yBEGIN ':' idAny/*new-block_identifier*/ { $$ = new AstBegin($1,*$3,NULL); SYMP->pushNew($$); }
	;

blockDeclStmtList:	// IEEE: { block_item_declaration } { statement or null }
	//			// The spec seems to suggest a empty declaration isn't ok, but most simulators take it
		block_item_declarationList		{ $$ = $1; }
	|	block_item_declarationList stmtList	{ $$ = $1->addNextNull($2); }
	|	stmtList				{ $$ = $1; }
	;

block_item_declarationList:	// IEEE: [ block_item_declaration ]
		block_item_declaration			{ $$ = $1; }
	|	block_item_declarationList block_item_declaration	{ $$ = $1->addNextNull($2); }
	;

block_item_declaration:	// ==IEEE: block_item_declaration
		data_declaration 			{ $$ = $1; }
	|	local_parameter_declaration 		{ $$ = $1; }
	|	parameter_declaration ';' 		{ $$ = $1; }
	//UNSUP	overload_declaration 			{ $$ = $1; }
	;

stmtList:
		stmtBlock				{ $$ = $1; }
	|	stmtList stmtBlock			{ $$ = ($2==NULL)?($1):($1->addNext($2)); }
	;

stmt:			// IEEE: statement_or_null == function_statement_or_null
		statement_item				{ }
	//UNSUP: Labeling any statement
	|	labeledStmt				{ $$ = $1; }
	|	id ':' labeledStmt			{ $$ = new AstBegin($2, *$1, $3); }  /*S05 block creation rule*/
	//			// from _or_null
	|	';'					{ $$ = NULL; }
	;

statement_item:		// IEEE: statement_item
	//			// IEEE: operator_assignment
		foperator_assignment ';'		{ $$ = $1; }
	//
	//		 	// IEEE: blocking_assignment
	//UNSUP	fexprLvalue '=' class_new ';'		{ UNSUP }
	//UNSUP	fexprLvalue '=' dynamic_array_new ';'	{ UNSUP }
	//
	//			// IEEE: nonblocking_assignment
	|	idClassSel yP_LTE delayE expr ';'	{ $$ = new AstAssignDly($2,$1,$4); }
	|	'{' variable_lvalueConcList '}' yP_LTE delayE expr ';' { $$ = new AstAssignDly($4,$2,$6); }
	//UNSUP	fexprLvalue yP_LTE delay_or_event_controlE expr ';'	{ UNSUP }
	//
	//			// IEEE: procedural_continuous_assignment
	|	yASSIGN idClassSel '=' delayE expr ';'	{ $$ = new AstAssign($1,$2,$5); }
	//UNSUP:			delay_or_event_controlE above
	//UNSUP	yDEASSIGN variable_lvalue ';'		{ UNSUP }
	//UNSUP	yFORCE expr '=' expr ';'		{ UNSUP }
	//UNSUP	yRELEASE variable_lvalue ';'		{ UNSUP }
	//
	//			// IEEE: case_statement
	|	unique_priorityE caseStart caseAttrE case_itemListE yENDCASE	{ $$ = $2; if ($4) $2->addItemsp($4);
							  if ($1 == uniq_UNIQUE) $2->uniquePragma(true);
							  if ($1 == uniq_UNIQUE0) $2->unique0Pragma(true);
							  if ($1 == uniq_PRIORITY) $2->priorityPragma(true); }
	//UNSUP	caseStart caseAttrE yMATCHES case_patternListE yENDCASE	{ }
	//UNSUP	caseStart caseAttrE yINSIDE  case_insideListE yENDCASE	{ }
	//
	//			// IEEE: conditional_statement
	|	unique_priorityE yIF '(' expr ')' stmtBlock	%prec prLOWER_THAN_ELSE
							{ $$ = new AstIf($2,$4,$6,NULL);
							  if ($1 == uniq_UNIQUE) $$->castIf()->uniquePragma(true);
							  if ($1 == uniq_UNIQUE0) $$->castIf()->unique0Pragma(true);
							  if ($1 == uniq_PRIORITY) $$->castIf()->priorityPragma(true); }
	|	unique_priorityE yIF '(' expr ')' stmtBlock yELSE stmtBlock
							{ $$ = new AstIf($2,$4,$6,$8);
							  if ($1 == uniq_UNIQUE) $$->castIf()->uniquePragma(true);
							  if ($1 == uniq_UNIQUE0) $$->castIf()->unique0Pragma(true);
							  if ($1 == uniq_PRIORITY) $$->castIf()->priorityPragma(true); }
	//
	|	finc_or_dec_expression ';'		{ $$ = $1; }
	//			// IEEE: inc_or_dec_expression
	//			// Below under expr
	//
	//			// IEEE: subroutine_call_statement
	//UNSUP	yVOID yP_TICK '(' function_subroutine_callNoMethod ')' ';' { }
	//UNSUP	yVOID yP_TICK '(' expr '.' function_subroutine_callNoMethod ')' ';' { }
	//			// Expr included here to resolve our not knowing what is a method call
	//			// Expr here must result in a subroutine_call
	|	task_subroutine_callNoMethod ';'	{ $$ = $1; }
	//UNSUP	fexpr '.' array_methodNoRoot ';'	{ UNSUP }
	//UNSUP	fexpr '.' task_subroutine_callNoMethod ';'	{ UNSUP }
	//UNSUP	fexprScope ';'				{ UNSUP }
	//			// Not here in IEEE; from class_constructor_declaration
	//			// Because we've joined class_constructor_declaration into generic functions
	//			// Way over-permissive;
	//			// IEEE: [ ySUPER '.' yNEW [ '(' list_of_arguments ')' ] ';' ]
	//UNSUP	fexpr '.' class_new ';'		{ }
	//
	|	statementVerilatorPragmas			{ $$ = $1; }
	//
	//			// IEEE: disable_statement
	|	yDISABLE idAny/*hierarchical_identifier-task_or_block*/ ';'	{ $$ = new AstDisable($1,*$2); }
	//UNSUP	yDISABLE yFORK ';'			{ UNSUP }
	//			// IEEE: event_trigger
	//UNSUP	yP_MINUSGT hierarchical_identifier/*event*/ ';'	{ UNSUP }
	//UNSUP	yP_MINUSGTGT delay_or_event_controlE hierarchical_identifier/*event*/ ';'	{ UNSUP }
	//			// IEEE: loop_statement
	|	yFOREVER stmtBlock			{ $$ = new AstWhile($1,new AstConst($1,AstConst::LogicTrue()),$2); }
	|	yREPEAT '(' expr ')' stmtBlock		{ $$ = new AstRepeat($1,$3,$5);}
	|	yWHILE '(' expr ')' stmtBlock		{ $$ = new AstWhile($1,$3,$5);}
	//			// for's first ';' is in for_initalization
	|	yFOR '(' for_initialization expr ';' for_stepE ')' stmtBlock
							{ $$ = new AstBegin($1,"",$3); $3->addNext(new AstWhile($1, $4,$8,$6)); }
	|	yDO stmtBlock yWHILE '(' expr ')' ';'	{ $$ = $2->cloneTree(true); $$->addNext(new AstWhile($1,$5,$2));}
	//UNSUP	yFOREACH '(' idClassForeach/*array_id[loop_variables]*/ ')' stmt	{ UNSUP }
	//
	//			// IEEE: jump_statement
	|	yRETURN ';'				{ $$ = new AstReturn($1); }
	|	yRETURN expr ';'			{ $$ = new AstReturn($1,$2); }
	|	yBREAK ';'				{ $$ = new AstBreak($1); }
	|	yCONTINUE ';'				{ $$ = new AstContinue($1); }
	//
	//UNSUP	par_block				{ $$ = $1; }
	//			// IEEE: procedural_timing_control_statement + procedural_timing_control
	|	delay_control stmtBlock			{ $$ = $2; $1->v3warn(STMTDLY,"Unsupported: Ignoring delay on this delayed statement."); }
	//UNSUP	event_control stmtBlock			{ UNSUP }
	//UNSUP	cycle_delay stmtBlock			{ UNSUP }
	//
	|	seq_block				{ $$ = $1; }
	//
	//			// IEEE: wait_statement
	//UNSUP	yWAIT '(' expr ')' stmtBlock		{ UNSUP }
	//UNSUP	yWAIT yFORK ';'				{ UNSUP }
	//UNSUP	yWAIT_ORDER '(' hierarchical_identifierList ')' action_block	{ UNSUP }
	//
	//			// IEEE: procedural_assertion_statement
	//			// Verilator: Label included instead
	|	concurrent_assertion_item		{ $$ = $1; }
	//			// concurrent_assertion_statement { $$ = $1; }
	//			// Verilator: Part of labeledStmt instead
	//			// immediate_assert_statement	{ UNSUP }
	//
	//			// IEEE: clocking_drive ';'
	//			// Pattern w/o cycle_delay handled by nonblocking_assign above
	//			// clockvar_expression made to fexprLvalue to prevent reduce conflict
	//			// Note LTE in this context is highest precedence, so first on left wins
	//UNSUP	cycle_delay fexprLvalue yP_LTE ';'	{ UNSUP }
	//UNSUP	fexprLvalue yP_LTE cycle_delay expr ';'	{ UNSUP }
	//
	//UNSUP	randsequence_statement			{ $$ = $1; }
	//
	//			// IEEE: randcase_statement
	//UNSUP	yRANDCASE case_itemList yENDCASE	{ UNSUP }
	//
	//UNSUP	expect_property_statement		{ $$ = $1; }
	//
	|	error ';'				{ $$ = NULL; }
	;

statementVerilatorPragmas:
		yVL_COVERAGE_BLOCK_OFF			{ $$ = new AstPragma($1,AstPragmaType::COVERAGE_BLOCK_OFF); }
	;

foperator_assignment:	// IEEE: operator_assignment (for first part of expression)
		idClassSel '=' delayE expr	{ $$ = new AstAssign($2,$1,$4); }
	|	idClassSel '=' yD_FOPEN '(' expr ',' expr ')'	{ $$ = new AstFOpen($3,$1,$5,$7); }
	|	'{' variable_lvalueConcList '}' '=' delayE expr	{ $$ = new AstAssign($4,$2,$6); }
	//
	//UNSUP	exprLvalue '=' delay_or_event_controlE expr { UNSUP }
	//UNSUP	exprLvalue yP_PLUS(etc) expr		{ UNSUP }
	|	idClassSel yP_PLUSEQ    expr		{ $$ = new AstAssign($2,$1,new AstAdd    ($2,$1->cloneTree(true),$3)); }
	|	idClassSel yP_MINUSEQ   expr		{ $$ = new AstAssign($2,$1,new AstSub    ($2,$1->cloneTree(true),$3)); }
	|	idClassSel yP_TIMESEQ   expr		{ $$ = new AstAssign($2,$1,new AstMul    ($2,$1->cloneTree(true),$3)); }
	|	idClassSel yP_DIVEQ     expr		{ $$ = new AstAssign($2,$1,new AstDiv    ($2,$1->cloneTree(true),$3)); }
	|	idClassSel yP_MODEQ     expr		{ $$ = new AstAssign($2,$1,new AstModDiv ($2,$1->cloneTree(true),$3)); }
	|	idClassSel yP_ANDEQ     expr		{ $$ = new AstAssign($2,$1,new AstAnd    ($2,$1->cloneTree(true),$3)); }
	|	idClassSel yP_OREQ      expr		{ $$ = new AstAssign($2,$1,new AstOr     ($2,$1->cloneTree(true),$3)); }
	|	idClassSel yP_XOREQ     expr		{ $$ = new AstAssign($2,$1,new AstXor    ($2,$1->cloneTree(true),$3)); }
	|	idClassSel yP_SLEFTEQ   expr		{ $$ = new AstAssign($2,$1,new AstShiftL ($2,$1->cloneTree(true),$3)); }
	|	idClassSel yP_SRIGHTEQ  expr		{ $$ = new AstAssign($2,$1,new AstShiftR ($2,$1->cloneTree(true),$3)); }
	|	idClassSel yP_SSRIGHTEQ expr		{ $$ = new AstAssign($2,$1,new AstShiftRS($2,$1->cloneTree(true),$3)); }
	//
	|	'{' variable_lvalueConcList '}' yP_PLUSEQ    expr	{ $$ = new AstAssign($4,$2,new AstAdd    ($4,$2->cloneTree(true),$5)); }
	|	'{' variable_lvalueConcList '}' yP_MINUSEQ   expr	{ $$ = new AstAssign($4,$2,new AstSub    ($4,$2->cloneTree(true),$5)); }
	|	'{' variable_lvalueConcList '}' yP_TIMESEQ   expr	{ $$ = new AstAssign($4,$2,new AstMul    ($4,$2->cloneTree(true),$5)); }
	|	'{' variable_lvalueConcList '}' yP_DIVEQ     expr	{ $$ = new AstAssign($4,$2,new AstDiv    ($4,$2->cloneTree(true),$5)); }
	|	'{' variable_lvalueConcList '}' yP_MODEQ     expr	{ $$ = new AstAssign($4,$2,new AstModDiv ($4,$2->cloneTree(true),$5)); }
	|	'{' variable_lvalueConcList '}' yP_ANDEQ     expr	{ $$ = new AstAssign($4,$2,new AstAnd    ($4,$2->cloneTree(true),$5)); }
	|	'{' variable_lvalueConcList '}' yP_OREQ      expr	{ $$ = new AstAssign($4,$2,new AstOr     ($4,$2->cloneTree(true),$5)); }
	|	'{' variable_lvalueConcList '}' yP_XOREQ     expr	{ $$ = new AstAssign($4,$2,new AstXor    ($4,$2->cloneTree(true),$5)); }
	|	'{' variable_lvalueConcList '}' yP_SLEFTEQ   expr	{ $$ = new AstAssign($4,$2,new AstShiftL ($4,$2->cloneTree(true),$5)); }
	|	'{' variable_lvalueConcList '}' yP_SRIGHTEQ  expr	{ $$ = new AstAssign($4,$2,new AstShiftR ($4,$2->cloneTree(true),$5)); }
	|	'{' variable_lvalueConcList '}' yP_SSRIGHTEQ expr	{ $$ = new AstAssign($4,$2,new AstShiftRS($4,$2->cloneTree(true),$5)); }
	;

finc_or_dec_expression:	// ==IEEE: inc_or_dec_expression
	//UNSUP: Generic scopes in incrementes
		varRefBase yP_PLUSPLUS			{ $$ = new AstAssign($2,$1,new AstAdd    ($2,$1->cloneTree(true),new AstConst($2,V3Number($2,"'b1")))); }
	|	varRefBase yP_MINUSMINUS		{ $$ = new AstAssign($2,$1,new AstSub    ($2,$1->cloneTree(true),new AstConst($2,V3Number($2,"'b1")))); }
	|	yP_PLUSPLUS   varRefBase		{ $$ = new AstAssign($1,$2,new AstAdd    ($1,$2->cloneTree(true),new AstConst($1,V3Number($1,"'b1")))); }
	|	yP_MINUSMINUS varRefBase		{ $$ = new AstAssign($1,$2,new AstSub    ($1,$2->cloneTree(true),new AstConst($1,V3Number($1,"'b1")))); }
	;

//************************************************
// Case/If

unique_priorityE:	// IEEE: unique_priority + empty
		/*empty*/				{ $$ = uniq_NONE; }
	|	yPRIORITY				{ $$ = uniq_PRIORITY; }
	|	yUNIQUE					{ $$ = uniq_UNIQUE; }
	|	yUNIQUE0				{ $$ = uniq_UNIQUE0; }
	;

caseStart:		// IEEE: part of case_statement
	 	yCASE  '(' expr ')' 			{ $$ = GRAMMARP->m_caseAttrp = new AstCase($1,AstCaseType::CT_CASE,$3,NULL); }
	|	yCASEX '(' expr ')' 			{ $$ = GRAMMARP->m_caseAttrp = new AstCase($1,AstCaseType::CT_CASEX,$3,NULL); }
	|	yCASEZ '(' expr ')'			{ $$ = GRAMMARP->m_caseAttrp = new AstCase($1,AstCaseType::CT_CASEZ,$3,NULL); }
	;

caseAttrE:
	 	/*empty*/				{ }
	|	caseAttrE yVL_FULL_CASE			{ GRAMMARP->m_caseAttrp->fullPragma(true); }
	|	caseAttrE yVL_PARALLEL_CASE		{ GRAMMARP->m_caseAttrp->parallelPragma(true); }
	;

case_itemListE:	// IEEE: [ { case_item } ]
		/* empty */				{ $$ = NULL; }
	|	case_itemList				{ $$ = $1; }
	;

case_itemList:	// IEEE: { case_item + ... }
		caseCondList ':' stmtBlock		{ $$ = new AstCaseItem($2,$1,$3); }
	|	yDEFAULT ':' stmtBlock			{ $$ = new AstCaseItem($2,NULL,$3); }
	|	yDEFAULT stmtBlock			{ $$ = new AstCaseItem($1,NULL,$2); }
	|	case_itemList caseCondList ':' stmtBlock	{ $$ = $1;$1->addNext(new AstCaseItem($3,$2,$4)); }
	|       case_itemList yDEFAULT stmtBlock		{ $$ = $1;$1->addNext(new AstCaseItem($2,NULL,$3)); }
	|	case_itemList yDEFAULT ':' stmtBlock		{ $$ = $1;$1->addNext(new AstCaseItem($3,NULL,$4)); }
	;

caseCondList:		// IEEE: part of case_item
		expr 					{ $$ = $1; }
	|	caseCondList ',' expr			{ $$ = $1;$1->addNext($3); }
	;

// "datatype id = x {, id = x }"  |  "yaId = x {, id=x}" is legal
for_initialization:	// ==IEEE: for_initialization + for_variable_declaration + extra terminating ";"
	//			// IEEE: for_variable_declaration
		varRESET data_type idAny/*new*/ '=' expr ';'
			{ VARDTYPE($2);
			  $$ = VARDONEA($<fl>3,*$3,NULL,NULL);
			  $$->addNext(new AstAssign($4,new AstVarRef($4,*$3,true),$5));}
	|	varRefBase '=' expr ';'			{ $$ = new AstAssign($2,$1,$3); }
	//UNSUP: List of initializations
	;

for_stepE:		// IEEE: for_step + empty
		/* empty */				{ $$ = NULL; }
	|	for_step				{ $$ = $1; }
	;

for_step:		// IEEE: for_step
		varRefBase '=' expr			{ $$ = new AstAssign($2,$1,$3); }
	|	yP_PLUSPLUS   varRefBase		{ $$ = new AstAssign($1,$2,new AstAdd ($1,$2->cloneTree(true),new AstConst($1,V3Number($1,"'b1")))) }
	|	yP_MINUSMINUS varRefBase		{ $$ = new AstAssign($1,$2,new AstSub ($1,$2->cloneTree(true),new AstConst($1,V3Number($1,"'b1")))) }
	|	varRefBase yP_PLUSPLUS			{ $$ = new AstAssign($2,$1,new AstAdd ($2,$1->cloneTree(true),new AstConst($2,V3Number($2,"'b1")))) }
	|	varRefBase yP_MINUSMINUS		{ $$ = new AstAssign($2,$1,new AstSub ($2,$1->cloneTree(true),new AstConst($2,V3Number($2,"'b1")))) }
	//UNSUP: List of steps
	;

//************************************************
// Functions/tasks

taskRef:		// IEEE: part of tf_call
		idDotted		 		{ $$ = new AstTaskRef($1->fileline(),new AstParseRef($1->fileline(), AstParseRefExp::PX_TASK, $1),NULL);}
	|	idDotted '(' list_of_argumentsE ')'	{ $$ = new AstTaskRef($1->fileline(),new AstParseRef($1->fileline(), AstParseRefExp::PX_TASK, $1),$3);}
	//UNSUP: package_scopeIdFollows idDotted		{ $$ = new AstTaskRef($1->fileline(),new AstParseRef($2->fileline(), AstParseRefExp::PX_TASK, $2),NULL);}
	//UNSUP: package_scopeIdFollows idDotted '(' list_of_argumentsE ')'	{ $$ = new AstTaskRef($1->fileline(),new AstParseRef($2->fileline(), AstParseRefExp::PX_TASK, $2),$4);}
	//UNSUP: idDotted is really just id to allow dotted method calls
	;

funcRef:		// IEEE: part of tf_call
		idDotted '(' list_of_argumentsE ')'	{ $$ = new AstFuncRef($2,new AstParseRef($1->fileline(), AstParseRefExp::PX_FUNC, $1), $3); }
	|	package_scopeIdFollows idDotted '(' list_of_argumentsE ')'	{ $$ = new AstFuncRef($3,new AstParseRef($2->fileline(), AstParseRefExp::PX_FUNC, $2), $4); $$->packagep($1); }
	//UNSUP: idDotted is really just id to allow dotted method calls
	;

task_subroutine_callNoMethod:	// function_subroutine_callNoMethod (as task)
	//			// IEEE: tf_call
		taskRef					{ $$ = $1; }
	|	system_t_call				{ $$ = $1; }
	//			// IEEE: method_call requires a "." so is in expr
	//UNSUP	randomize_call 				{ $$ = $1; }
	;

function_subroutine_callNoMethod:	// IEEE: function_subroutine_call (as function)
	//			// IEEE: tf_call
		funcRef					{ $$ = $1; }
	|	system_f_call				{ $$ = $1; }
	//			// IEEE: method_call requires a "." so is in expr
	//UNSUP	randomize_call 				{ $$ = $1; }
	;

system_t_call:		// IEEE: system_tf_call (as task)
	//
		yaD_IGNORE  parenE			{ $$ = new AstSysIgnore($<fl>1,NULL); }
	|	yaD_IGNORE  '(' exprList ')'		{ $$ = new AstSysIgnore($<fl>1,$3); }
	//
	|	yaD_DPI parenE				{ $$ = new AstTaskRef($<fl>1,*$1,NULL); }
	|	yaD_DPI '(' exprList ')'		{ $$ = new AstTaskRef($2,*$1,$3); }
	//
	|	yD_C '(' cStrList ')'			{ $$ = (v3Global.opt.ignc() ? NULL : new AstUCStmt($1,$3)); }
	|	yD_FCLOSE '(' idClassSel ')'		{ $$ = new AstFClose($1, $3); }
	|	yD_FFLUSH parenE			{ $1->v3error("Unsupported: $fflush of all handles does not map to C++."); }
	|	yD_FFLUSH '(' idClassSel ')'		{ $$ = new AstFFlush($1, $3); }
	|	yD_FINISH parenE			{ $$ = new AstFinish($1); }
	|	yD_FINISH '(' expr ')'			{ $$ = new AstFinish($1); }
	|	yD_STOP parenE				{ $$ = new AstStop($1); }
	|	yD_STOP '(' expr ')'			{ $$ = new AstStop($1); }
	//
	|	yD_SFORMAT '(' expr ',' str commaEListE ')'	{ $$ = new AstSFormat($1,$3,*$5,$6); }
	|	yD_SWRITE  '(' expr ',' str commaEListE ')'	{ $$ = new AstSFormat($1,$3,*$5,$6); }
	|	yD_SYSTEM  '(' expr ')'				{ $$ = new AstSystemT($1,$3); }
	//
	|	yD_DISPLAY  parenE					{ $$ = new AstDisplay($1,AstDisplayType::DT_DISPLAY,"", NULL,NULL); }
	|	yD_DISPLAY  '(' str commaEListE ')'			{ $$ = new AstDisplay($1,AstDisplayType::DT_DISPLAY,*$3,NULL,$4); }
	|	yD_WRITE    parenE					{ $$ = NULL; } // NOP
	|	yD_WRITE    '(' str commaEListE ')'			{ $$ = new AstDisplay($1,AstDisplayType::DT_WRITE,  *$3,NULL,$4); }
	|	yD_FDISPLAY '(' idClassSel ')'			 	{ $$ = new AstDisplay($1,AstDisplayType::DT_DISPLAY,"",$3,NULL); }
	|	yD_FDISPLAY '(' idClassSel ',' str commaEListE ')' 	{ $$ = new AstDisplay($1,AstDisplayType::DT_DISPLAY,*$5,$3,$6); }
	|	yD_FWRITE   '(' idClassSel ',' str commaEListE ')'	{ $$ = new AstDisplay($1,AstDisplayType::DT_WRITE,  *$5,$3,$6); }
	|	yD_INFO	    parenE					{ $$ = new AstDisplay($1,AstDisplayType::DT_INFO,   "", NULL,NULL); }
	|	yD_INFO	    '(' str commaEListE ')'			{ $$ = new AstDisplay($1,AstDisplayType::DT_INFO,   *$3,NULL,$4); }
	|	yD_WARNING  parenE					{ $$ = new AstDisplay($1,AstDisplayType::DT_WARNING,"", NULL,NULL); }
	|	yD_WARNING  '(' str commaEListE ')'			{ $$ = new AstDisplay($1,AstDisplayType::DT_WARNING,*$3,NULL,$4); }
	|	yD_ERROR    parenE					{ $$ = GRAMMARP->createDisplayError($1); }
	|	yD_ERROR    '(' str commaEListE ')'			{ $$ = new AstDisplay($1,AstDisplayType::DT_ERROR,  *$3,NULL,$4);   $$->addNext(new AstStop($1)); }
	|	yD_FATAL    parenE					{ $$ = new AstDisplay($1,AstDisplayType::DT_FATAL,  "", NULL,NULL); $$->addNext(new AstStop($1)); }
	|	yD_FATAL    '(' expr ')'				{ $$ = new AstDisplay($1,AstDisplayType::DT_FATAL,  "", NULL,NULL); $$->addNext(new AstStop($1)); if ($3) $3->deleteTree(); }
	|	yD_FATAL    '(' expr ',' str commaEListE ')'		{ $$ = new AstDisplay($1,AstDisplayType::DT_FATAL,  *$5,NULL,$6);   $$->addNext(new AstStop($1)); if ($3) $3->deleteTree(); }
	//
	|	yD_READMEMB '(' expr ',' varRefMem ')'				{ $$ = new AstReadMem($1,false,$3,$5,NULL,NULL); }
	|	yD_READMEMB '(' expr ',' varRefMem ',' expr ')'			{ $$ = new AstReadMem($1,false,$3,$5,$7,NULL); }
	|	yD_READMEMB '(' expr ',' varRefMem ',' expr ',' expr ')'	{ $$ = new AstReadMem($1,false,$3,$5,$7,$9); }
	|	yD_READMEMH '(' expr ',' varRefMem ')'				{ $$ = new AstReadMem($1,true, $3,$5,NULL,NULL); }
	|	yD_READMEMH '(' expr ',' varRefMem ',' expr ')'			{ $$ = new AstReadMem($1,true, $3,$5,$7,NULL); }
	|	yD_READMEMH '(' expr ',' varRefMem ',' expr ',' expr ')'	{ $$ = new AstReadMem($1,true, $3,$5,$7,$9); }
	;

system_f_call:		// IEEE: system_tf_call (as func)
		yaD_IGNORE parenE			{ $$ = new AstConst($<fl>1,V3Number($<fl>1,"'b0")); } // Unsized 0
	|	yaD_IGNORE '(' exprList ')'		{ $$ = new AstConst($2,V3Number($2,"'b0")); } // Unsized 0
	//
	|	yaD_DPI parenE				{ $$ = new AstFuncRef($<fl>1,*$1,NULL); }
	|	yaD_DPI '(' exprList ')'		{ $$ = new AstFuncRef($2,*$1,$3); }
	//
	|	yD_CEIL '(' expr ')'			{ $$ = new AstCeilD($1,$3); }
	|	yD_EXP '(' expr ')'			{ $$ = new AstExpD($1,$3); }
	|	yD_FLOOR '(' expr ')'			{ $$ = new AstFloorD($1,$3); }
	|	yD_LN '(' expr ')'			{ $$ = new AstLogD($1,$3); }
	|	yD_LOG10 '(' expr ')'			{ $$ = new AstLog10D($1,$3); }
	|	yD_POW '(' expr ',' expr ')'		{ $$ = new AstPowD($1,$3,$5); }
	|	yD_SQRT '(' expr ')'			{ $$ = new AstSqrtD($1,$3); }
	|	yD_BITS '(' expr ')'			{ $$ = new AstAttrOf($1,AstAttrType::EXPR_BITS,$3); }
	|	yD_BITS '(' data_type ')'		{ $$ = new AstAttrOf($1,AstAttrType::EXPR_BITS,$3); }
	|	yD_BITSTOREAL '(' expr ')'		{ $$ = new AstBitsToRealD($1,$3); }
	|	yD_C '(' cStrList ')'			{ $$ = (v3Global.opt.ignc() ? NULL : new AstUCFunc($1,$3)); }
	|	yD_CLOG2 '(' expr ')'			{ $$ = new AstCLog2($1,$3); }
	|	yD_COUNTONES '(' expr ')'		{ $$ = new AstCountOnes($1,$3); }
	|	yD_FEOF '(' expr ')'			{ $$ = new AstFEof($1,$3); }
	|	yD_FGETC '(' expr ')'			{ $$ = new AstFGetC($1,$3); }
	|	yD_FGETS '(' idClassSel ',' expr ')'	{ $$ = new AstFGetS($1,$3,$5); }
	|	yD_FSCANF '(' expr ',' str commaVRDListE ')'	{ $$ = new AstFScanF($1,*$5,$3,$6); }
	|	yD_SSCANF '(' expr ',' str commaVRDListE ')'	{ $$ = new AstSScanF($1,*$5,$3,$6); }
	|	yD_SYSTEM  '(' expr ')'				{ $$ = new AstSystemF($1,$3); }
	|	yD_ISUNKNOWN '(' expr ')'		{ $$ = new AstIsUnknown($1,$3); }
	|	yD_ITOR '(' expr ')'			{ $$ = new AstIToRD($1,$3); }
	|	yD_ONEHOT '(' expr ')'			{ $$ = new AstOneHot($1,$3); }
	|	yD_ONEHOT0 '(' expr ')'			{ $$ = new AstOneHot0($1,$3); }
	|	yD_RANDOM '(' expr ')'			{ $1->v3error("Unsupported: Seeding $random doesn't map to C++, use $c(\"srand\")"); }
	|	yD_RANDOM parenE			{ $$ = new AstRand($1); }
	|	yD_REALTIME parenE			{ $$ = new AstTimeD($1); }
	|	yD_REALTOBITS '(' expr ')'		{ $$ = new AstRealToBits($1,$3); }
	|	yD_RTOI '(' expr ')'			{ $$ = new AstRToIS($1,$3); }
	//|	yD_SFORMATF '(' str commaEListE ')'	{ $$ = new AstSFormatF($1,*$3,false,$4); }  // Have AST, just need testing and debug
	|	yD_SIGNED '(' expr ')'			{ $$ = new AstSigned($1,$3); }
	|	yD_STIME parenE				{ $$ = new AstSel($1,new AstTime($1),0,32); }
	|	yD_TIME	parenE				{ $$ = new AstTime($1); }
	|	yD_TESTPLUSARGS '(' str ')'		{ $$ = new AstTestPlusArgs($1,*$3); }
	|	yD_UNSIGNED '(' expr ')'		{ $$ = new AstUnsigned($1,$3); }
	|	yD_VALUEPLUSARGS '(' str ',' expr ')'	{ $$ = new AstValuePlusArgs($1,*$3,$5); }
	;

list_of_argumentsE:	// IEEE: [list_of_arguments]
		/* empty */				{ $$ = NULL; }
	|	argsExprList				{ $$ = $1; }
	//UNSUP empty arguments with just ,,
	;

task_declaration:	// ==IEEE: task_declaration
		yTASK lifetimeE taskId tfGuts yENDTASK endLabelE
			{ $$ = $3; $$->addStmtsp($4); SYMP->popScope($$);
			  GRAMMARP->endLabel($<fl>6,$$,$6); }
	;

task_prototype:		// ==IEEE: task_prototype
		yTASK taskId '(' tf_port_listE ')'	{ $$=$2; $$->addStmtsp($4); $$->prototype(true); SYMP->popScope($$); }
	;

function_declaration:	// IEEE: function_declaration + function_body_declaration
	 	yFUNCTION lifetimeE funcId funcIsolateE tfGuts yENDFUNCTION endLabelE
			{ $$ = $3; $3->attrIsolateAssign($4); $$->addStmtsp($5);
			  SYMP->popScope($$);
			  GRAMMARP->endLabel($<fl>7,$$,$7); }
	;

function_prototype:	// IEEE: function_prototype
		yFUNCTION funcId '(' tf_port_listE ')'	{ $$=$2; $$->addStmtsp($4); $$->prototype(true); SYMP->popScope($$); }
	;

funcIsolateE:
		/* empty */		 		{ $$ = 0; }
	|	yVL_ISOLATE_ASSIGNMENTS			{ $$ = 1; }
	;

lifetimeE:			// IEEE: [lifetime]
		/* empty */		 		{ }
	|	lifetime		 		{ }
	;

lifetime:			// ==IEEE: lifetime
	//			// Note lifetime used by members is instead under memberQual
		ySTATIC			 		{ $1->v3error("Unsupported: Static in this context"); }
	|	yAUTOMATIC		 		{ }
	;

taskId:
		tfIdScoped
			{ $$ = new AstTask($<fl>1, *$<strp>1, NULL);
			  SYMP->pushNewUnder($$, NULL); }
	;

funcId:			// IEEE: function_data_type_or_implicit + part of function_body_declaration
	//			// IEEE: function_data_type_or_implicit must be expanded here to prevent conflict
	//			// function_data_type expanded here to prevent conflicts with implicit_type:empty vs data_type:ID
		/**/			tfIdScoped
			{ $$ = new AstFunc ($<fl>1,*$<strp>1,NULL,
					    new AstBasicDType($<fl>1, LOGIC_IMPLICIT));
			  SYMP->pushNewUnder($$, NULL); }
	|	signingE rangeList	tfIdScoped
			{ $$ = new AstFunc ($<fl>3,*$<strp>3,NULL,
					    GRAMMARP->addRange(new AstBasicDType($<fl>3, LOGIC_IMPLICIT, $1), $2,false));
			  SYMP->pushNewUnder($$, NULL); }
	|	signing			tfIdScoped
			{ $$ = new AstFunc ($<fl>2,*$<strp>2,NULL,
					    new AstBasicDType($<fl>2, LOGIC_IMPLICIT, $1));
			  SYMP->pushNewUnder($$, NULL); }
	|	data_type		tfIdScoped
			{ $$ = new AstFunc ($<fl>2,*$<strp>2,NULL,$1);
			  SYMP->pushNewUnder($$, NULL); }
	//			// To verilator tasks are the same as void functions (we separately detect time passing)
	|	yVOID			tfIdScoped
			{ $$ = new AstTask ($<fl>2,*$<strp>2,NULL);
			  SYMP->pushNewUnder($$, NULL); }
	;

tfIdScoped:		// IEEE: part of function_body_declaration/task_body_declaration
 	//			// IEEE: [ interface_identifier '.' | class_scope ] function_identifier
		id					{ $<fl>$=$<fl>1; $<strp>$ = $1; }
	//UNSUP	id/*interface_identifier*/ '.' id	{ UNSUP }
	//UNSUP	class_scope_id				{ UNSUP }
	;

tfGuts:
		'(' tf_port_listE ')' ';' tfBodyE	{ $$ = $2->addNextNull($5); }
	|	';' tfBodyE				{ $$ = $2; }
	;

tfBodyE:			// IEEE: part of function_body_declaration/task_body_declaration
		/* empty */				{ $$ = NULL; }
	|	tf_item_declarationList			{ $$ = $1; }
	|	tf_item_declarationList stmtList	{ $$ = $1->addNextNull($2); }
	|	stmtList				{ $$ = $1; }
	;

tf_item_declarationList:
		tf_item_declaration			{ $$ = $1; }
	|	tf_item_declarationList tf_item_declaration	{ $$ = $1->addNextNull($2); }
	;

tf_item_declaration:	// ==IEEE: tf_item_declaration
		block_item_declaration			{ $$ = $1; }
	|	tf_port_declaration			{ $$ = $1; }
	|	tf_item_declarationVerilator		{ $$ = $1; }
	;

tf_item_declarationVerilator:	// Verilator extensions
		yVL_PUBLIC				{ $$ = new AstPragma($1,AstPragmaType::PUBLIC_TASK); }
	|	yVL_NO_INLINE_TASK			{ $$ = new AstPragma($1,AstPragmaType::NO_INLINE_TASK); }
	;

tf_port_listE:		// IEEE: tf_port_list + empty
	//			// Empty covered by tf_port_item
		{VARRESET_LIST(UNKNOWN); VARIO(INPUT); }
			tf_port_listList		{ $$ = $2; VARRESET_NONLIST(UNKNOWN); }
	;

tf_port_listList:	// IEEE: part of tf_port_list
		tf_port_item				{ $$ = $1; }
	|	tf_port_listList ',' tf_port_item	{ $$ = $1->addNextNull($3); }
	;

tf_port_item:		// ==IEEE: tf_port_item
	//			// We split tf_port_item into the type and assignment as don't know what follows a comma
		/* empty */				{ $$ = NULL; PINNUMINC(); }	// For example a ",," port
	|	tf_port_itemFront tf_port_itemAssignment { $$ = $2; }
	|	tf_port_itemAssignment 			{ $$ = $1; }
	;

tf_port_itemFront:		// IEEE: part of tf_port_item, which has the data type
		data_type				{ VARDTYPE($1); }
	|	signingE rangeList			{ VARDTYPE(GRAMMARP->addRange(new AstBasicDType($2->fileline(), LOGIC_IMPLICIT, $1), $2, false)); }
	|	signing					{ VARDTYPE(new AstBasicDType($<fl>1, LOGIC_IMPLICIT, $1)); }
	|	yVAR data_type				{ VARDTYPE($2); }
	|	yVAR implicit_typeE			{ VARDTYPE($2); }
	//
	|	tf_port_itemDir /*implicit*/		{ VARDTYPE(NULL); /*default_nettype-see spec*/ }
	|	tf_port_itemDir data_type		{ VARDTYPE($2); }
	|	tf_port_itemDir signingE rangeList	{ VARDTYPE(GRAMMARP->addRange(new AstBasicDType($3->fileline(), LOGIC_IMPLICIT, $2),$3,false)); }
	|	tf_port_itemDir signing			{ VARDTYPE(new AstBasicDType($<fl>2, LOGIC_IMPLICIT, $2)); }
	|	tf_port_itemDir yVAR data_type		{ VARDTYPE($3); }
	|	tf_port_itemDir yVAR implicit_typeE	{ VARDTYPE($3); }
	;

tf_port_itemDir:		// IEEE: part of tf_port_item, direction
		port_direction				{ }  // port_direction sets VARIO
	;

tf_port_itemAssignment:	// IEEE: part of tf_port_item, which has assignment
		id variable_dimensionListE sigAttrListE
			{ $$ = VARDONEA($<fl>1, *$1, $2, $3); }
	|	id variable_dimensionListE sigAttrListE '=' expr
			{ $$ = VARDONEA($<fl>1, *$1, $2, $3); $$->valuep($5); }
	;

parenE:
		/* empty */				{ }
	|	'(' ')'					{ }
	;

//	method_call:		// ==IEEE: method_call + method_call_body
//				// IEEE: method_call_root '.' method_identifier [ '(' list_of_arguments ')' ]
//				//   "method_call_root '.' method_identifier" looks just like "expr '.' id"
//				//   "method_call_root '.' method_identifier (...)" looks just like "expr '.' tf_call"
//				// IEEE: built_in_method_call
//				//   method_call_root not needed, part of expr resolution
//				// What's left is below array_methodNoRoot

dpi_import_export:	// ==IEEE: dpi_import_export
		yIMPORT yaSTRING dpi_tf_import_propertyE dpi_importLabelE function_prototype ';'
			{ $$ = $5; if (*$4!="") $5->cname(*$4); $5->dpiContext($3==iprop_CONTEXT); $5->pure($3==iprop_PURE);
			  $5->dpiImport(true); GRAMMARP->checkDpiVer($1,*$2); v3Global.dpi(true);
			  if ($$->prettyName()[0]=='$') SYMP->reinsert($$,NULL,$$->prettyName());  // For $SysTF overriding
			  SYMP->reinsert($$); }
	|	yIMPORT yaSTRING dpi_tf_import_propertyE dpi_importLabelE task_prototype ';'
			{ $$ = $5; if (*$4!="") $5->cname(*$4); $5->dpiContext($3==iprop_CONTEXT); $5->pure($3==iprop_PURE);
			  $5->dpiImport(true); $5->dpiTask(true); GRAMMARP->checkDpiVer($1,*$2); v3Global.dpi(true);
			  if ($$->prettyName()[0]=='$') SYMP->reinsert($$,NULL,$$->prettyName());  // For $SysTF overriding
			  SYMP->reinsert($$); }
	|	yEXPORT yaSTRING dpi_importLabelE yFUNCTION idAny ';'	{ $$ = new AstDpiExport($1,*$5,*$3);
			  GRAMMARP->checkDpiVer($1,*$2); v3Global.dpi(true); }
	|	yEXPORT yaSTRING dpi_importLabelE yTASK     idAny ';'	{ $$ = new AstDpiExport($1,*$5,*$3);
			  GRAMMARP->checkDpiVer($1,*$2); v3Global.dpi(true); }
	;

dpi_importLabelE:		// IEEE: part of dpi_import_export
		/* empty */				{ static string s = ""; $$ = &s; }
	|	idAny/*c_identifier*/ '='		{ $$ = $1; $<fl>$=$<fl>1; }
	;

dpi_tf_import_propertyE:	// IEEE: [ dpi_function_import_property + dpi_task_import_property ]
		/* empty */				{ $$ = iprop_NONE; }
	|	yCONTEXT				{ $$ = iprop_CONTEXT; }
	|	yPURE					{ $$ = iprop_PURE; }
	;

//************************************************
// Expressions
//
//  means this is the (l)eft hand side of any operator
//     it will get replaced by "", "f" or "s"equence
//  means this is a (r)ight hand later expansion in the same statement,
//     not under parenthesis for <= disambiguation
//     it will get replaced by "", or "f"
//  means this is a (p)arenthetized expression
//     it will get replaced by "", or "s"equence

constExpr:
		expr					{ $$ = $1; }
	;

expr:			// IEEE: part of expression/constant_expression/primary
	// *SEE BELOW*		// IEEE: primary/constant_primary
	//
	//			// IEEE: unary_operator primary
		'+' expr	%prec prUNARYARITH	{ $$ = $2; }
	|	'-' expr	%prec prUNARYARITH	{ $$ = new AstNegate	($1,$2); }
	|	'!' expr	%prec prNEGATION	{ $$ = new AstLogNot	($1,$2); }
	|	'&' expr	%prec prREDUCTION	{ $$ = new AstRedAnd	($1,$2); }
	|	'~' expr	%prec prNEGATION	{ $$ = new AstNot	($1,$2); }
	|	'|' expr	%prec prREDUCTION	{ $$ = new AstRedOr	($1,$2); }
	|	'^' expr	%prec prREDUCTION	{ $$ = new AstRedXor	($1,$2); }
	|	yP_NAND expr	%prec prREDUCTION	{ $$ = new AstNot($1,new AstRedAnd($1,$2)); }
	|	yP_NOR  expr	%prec prREDUCTION	{ $$ = new AstNot($1,new AstRedOr ($1,$2)); }
	|	yP_XNOR expr	%prec prREDUCTION	{ $$ = new AstRedXnor	($1,$2); }
	//
	//			// IEEE: inc_or_dec_expression
	//UNSUP	inc_or_dec_expression		{ UNSUP }
	//
	//			// IEEE: '(' operator_assignment ')'
	//			// Need exprScope of variable_lvalue to prevent conflict
	//UNSUP	'(' exprScope '=' 	      expr ')'	{ UNSUP }
	//UNSUP	'(' exprScope yP_PLUSEQ    expr ')'	{ UNSUP }
	//UNSUP	'(' exprScope yP_MINUSEQ   expr ')'	{ UNSUP }
	//UNSUP	'(' exprScope yP_TIMESEQ   expr ')'	{ UNSUP }
	//UNSUP	'(' exprScope yP_DIVEQ     expr ')'	{ UNSUP }
	//UNSUP	'(' exprScope yP_MODEQ     expr ')'	{ UNSUP }
	//UNSUP	'(' exprScope yP_ANDEQ     expr ')'	{ UNSUP }
	//UNSUP	'(' exprScope yP_OREQ      expr ')'	{ UNSUP }
	//UNSUP	'(' exprScope yP_XOREQ     expr ')'	{ UNSUP }
	//UNSUP	'(' exprScope yP_SLEFTEQ   expr ')'	{ UNSUP }
	//UNSUP	'(' exprScope yP_SRIGHTEQ  expr ')'	{ UNSUP }
	//UNSUP	'(' exprScope yP_SSRIGHTEQ expr ')'	{ UNSUP }
	//
	//			// IEEE: expression binary_operator expression
	|	expr '+' expr			{ $$ = new AstAdd	($2,$1,$3); }
	|	expr '-' expr			{ $$ = new AstSub	($2,$1,$3); }
	|	expr '*' expr			{ $$ = new AstMul	($2,$1,$3); }
	|	expr '/' expr			{ $$ = new AstDiv	($2,$1,$3); }
	|	expr '%' expr			{ $$ = new AstModDiv	($2,$1,$3); }
	|	expr yP_EQUAL expr		{ $$ = new AstEq	($2,$1,$3); }
	|	expr yP_NOTEQUAL expr		{ $$ = new AstNeq	($2,$1,$3); }
	|	expr yP_CASEEQUAL expr		{ $$ = new AstEqCase	($2,$1,$3); }
	|	expr yP_CASENOTEQUAL expr		{ $$ = new AstNeqCase	($2,$1,$3); }
	|	expr yP_WILDEQUAL expr		{ $$ = new AstEqWild	($2,$1,$3); }
	|	expr yP_WILDNOTEQUAL expr		{ $$ = new AstNeqWild	($2,$1,$3); }
	|	expr yP_ANDAND expr		{ $$ = new AstLogAnd	($2,$1,$3); }
	|	expr yP_OROR expr			{ $$ = new AstLogOr	($2,$1,$3); }
	|	expr yP_POW expr			{ $$ = new AstPow	($2,$1,$3); }
	|	expr '<' expr			{ $$ = new AstLt	($2,$1,$3); }
	|	expr '>' expr			{ $$ = new AstGt	($2,$1,$3); }
	|	expr yP_GTE expr			{ $$ = new AstGte	($2,$1,$3); }
	|	expr '&' expr			{ $$ = new AstAnd	($2,$1,$3); }
	|	expr '|' expr			{ $$ = new AstOr	($2,$1,$3); }
	|	expr '^' expr			{ $$ = new AstXor	($2,$1,$3); }
	|	expr yP_XNOR expr			{ $$ = new AstXnor	($2,$1,$3); }
	|	expr yP_NOR expr			{ $$ = new AstNot($2,new AstOr	($2,$1,$3)); }
	|	expr yP_NAND expr			{ $$ = new AstNot($2,new AstAnd	($2,$1,$3)); }
	|	expr yP_SLEFT expr		{ $$ = new AstShiftL	($2,$1,$3); }
	|	expr yP_SRIGHT expr		{ $$ = new AstShiftR	($2,$1,$3); }
	|	expr yP_SSRIGHT expr		{ $$ = new AstShiftRS	($2,$1,$3); }
	//			// <= is special, as we need to disambiguate it with <= assignment
	//			// We copy all of expr to fexpr and rename this token to a fake one.
	|	expr yP_LTE expr	{ $$ = new AstLte	($2,$1,$3); }
	//
	//			// IEEE: conditional_expression
	|	expr '?' expr ':' expr		{ $$ = new AstCond($2,$1,$3,$5); }
	//
	//			// IEEE: inside_expression
	//UNSUP	expr yINSIDE '{' open_range_list '}'	{ UNSUP }
	//
	//			// IEEE: tagged_union_expression
	//UNSUP	yTAGGED id/*member*/ %prec prTAGGED		{ UNSUP }
	//UNSUP	yTAGGED id/*member*/ %prec prTAGGED expr	{ UNSUP }
	//
	//======================// PSL expressions
	//
	|	expr yP_MINUSGT expr		{ $$ = new AstLogIf	($2,$1,$3); }
	|	expr yP_LOGIFF expr		{ $$ = new AstLogIff	($2,$1,$3); }
	//
	//======================// IEEE: primary/constant_primary
	//
	//			// IEEE: primary_literal (minus string, which is handled specially)
	|	yaINTNUM				{ $$ = new AstConst($<fl>1,*$1); }
	|	yaFLOATNUM				{ $$ = new AstConst($<fl>1,AstConst::RealDouble(),$1); }
	//UNSUP	yaTIMENUM				{ UNSUP }
	|	strAsInt			{ $$ = $1; }
	//
	//			// IEEE: "... hierarchical_identifier select"  see below
	//
	//			// IEEE: empty_queue
	//UNSUP	'{' '}'
	//
	//			// IEEE: concatenation/constant_concatenation
	//			// Part of exprOkLvalue below
	//
	//			// IEEE: multiple_concatenation/constant_multiple_concatenation
	|	'{' constExpr '{' cateList '}' '}'	{ $$ = new AstReplicate($1,$4,$2); }
	//
	|	function_subroutine_callNoMethod	{ $$ = $1; }
	//			// method_call
	//UNSUP	expr '.' function_subroutine_callNoMethod	{ UNSUP }
	//			// method_call:array_method requires a '.'
	//UNSUP	expr '.' array_methodNoRoot		{ UNSUP }
	//
	//			// IEEE: '(' mintypmax_expression ')'
	|	'(' expr ')'		{ $$ = $2; }
	//UNSUP	'(' expr ':' expr ':' expr ')'	{ $$ = $4; }
	//			// PSL rule
	|	'_' '(' statePushVlg expr statePop ')'	{ $$ = $4; }	// Arbitrary Verilog inside PSL
	//
	//			// IEEE: cast/constant_cast
	|	casting_type yP_TICK '(' expr ')'	{ $$ = new AstCast($2,$4,$1); }
	//			// expanded from casting_type
	|	ySIGNED	     yP_TICK '(' expr ')'	{ $$ = new AstSigned($1,$4); }
	|	yUNSIGNED    yP_TICK '(' expr ')'	{ $$ = new AstUnsigned($1,$4); }
	//			// Spec only allows primary with addition of a type reference
	//			// We'll be more general, and later assert LHS was a type.
	//UNSUP	expr yP_TICK '(' expr ')'		{ UNSUP }
	//
	//			// IEEE: assignment_pattern_expression
	//			// IEEE: streaming_concatenation
	//			// See exprOkLvalue
	//
	//			// IEEE: sequence_method_call
	//			// Indistinguishable from function_subroutine_call:method_call
	//
	//UNSUP	'$'					{ UNSUP }
	//UNSUP	yNULL					{ UNSUP }
	//			// IEEE: yTHIS
	//			// See exprScope
	//
	//----------------------
	//
	|	exprOkLvalue				{ $$ = $1; }
	//
	//----------------------
	//
	//			// IEEE: cond_predicate - here to avoid reduce problems
	//			// Note expr includes cond_pattern
	//UNSUP	expr yP_ANDANDAND expr		{ UNSUP }
	//
	//			// IEEE: cond_pattern - here to avoid reduce problems
	//			// "expr yMATCHES pattern"
	//			// IEEE: pattern - expanded here to avoid conflicts
	//UNSUP	expr yMATCHES patternNoExpr		{ UNSUP }
	//UNSUP	expr yMATCHES expr		{ UNSUP }
	//
	//			// IEEE: expression_or_dist - here to avoid reduce problems
	//			// "expr yDIST '{' dist_list '}'"
	//UNSUP	expr yDIST '{' dist_list '}'		{ UNSUP }
	;

exprNoStr:		// expression with string removed
		 		'+' expr	%prec prUNARYARITH	{ $$ = $2; } 	|	'-' expr	%prec prUNARYARITH	{ $$ = new AstNegate	($1,$2); } 	|	'!' expr	%prec prNEGATION	{ $$ = new AstLogNot	($1,$2); } 	|	'&' expr	%prec prREDUCTION	{ $$ = new AstRedAnd	($1,$2); } 	|	'~' expr	%prec prNEGATION	{ $$ = new AstNot	($1,$2); } 	|	'|' expr	%prec prREDUCTION	{ $$ = new AstRedOr	($1,$2); } 	|	'^' expr	%prec prREDUCTION	{ $$ = new AstRedXor	($1,$2); } 	|	yP_NAND expr	%prec prREDUCTION	{ $$ = new AstNot($1,new AstRedAnd($1,$2)); } 	|	yP_NOR  expr	%prec prREDUCTION	{ $$ = new AstNot($1,new AstRedOr ($1,$2)); } 	|	yP_XNOR expr	%prec prREDUCTION	{ $$ = new AstRedXnor	($1,$2); } 	|	expr '+' expr			{ $$ = new AstAdd	($2,$1,$3); } 	|	expr '-' expr			{ $$ = new AstSub	($2,$1,$3); } 	|	expr '*' expr			{ $$ = new AstMul	($2,$1,$3); } 	|	expr '/' expr			{ $$ = new AstDiv	($2,$1,$3); } 	|	expr '%' expr			{ $$ = new AstModDiv	($2,$1,$3); } 	|	expr yP_EQUAL expr		{ $$ = new AstEq	($2,$1,$3); } 	|	expr yP_NOTEQUAL expr		{ $$ = new AstNeq	($2,$1,$3); } 	|	expr yP_CASEEQUAL expr		{ $$ = new AstEqCase	($2,$1,$3); } 	|	expr yP_CASENOTEQUAL expr		{ $$ = new AstNeqCase	($2,$1,$3); } 	|	expr yP_WILDEQUAL expr		{ $$ = new AstEqWild	($2,$1,$3); } 	|	expr yP_WILDNOTEQUAL expr		{ $$ = new AstNeqWild	($2,$1,$3); } 	|	expr yP_ANDAND expr		{ $$ = new AstLogAnd	($2,$1,$3); } 	|	expr yP_OROR expr			{ $$ = new AstLogOr	($2,$1,$3); } 	|	expr yP_POW expr			{ $$ = new AstPow	($2,$1,$3); } 	|	expr '<' expr			{ $$ = new AstLt	($2,$1,$3); } 	|	expr '>' expr			{ $$ = new AstGt	($2,$1,$3); } 	|	expr yP_GTE expr			{ $$ = new AstGte	($2,$1,$3); } 	|	expr '&' expr			{ $$ = new AstAnd	($2,$1,$3); } 	|	expr '|' expr			{ $$ = new AstOr	($2,$1,$3); } 	|	expr '^' expr			{ $$ = new AstXor	($2,$1,$3); } 	|	expr yP_XNOR expr			{ $$ = new AstXnor	($2,$1,$3); } 	|	expr yP_NOR expr			{ $$ = new AstNot($2,new AstOr	($2,$1,$3)); } 	|	expr yP_NAND expr			{ $$ = new AstNot($2,new AstAnd	($2,$1,$3)); } 	|	expr yP_SLEFT expr		{ $$ = new AstShiftL	($2,$1,$3); } 	|	expr yP_SRIGHT expr		{ $$ = new AstShiftR	($2,$1,$3); } 	|	expr yP_SSRIGHT expr		{ $$ = new AstShiftRS	($2,$1,$3); } 	|	expr yP_LTE expr	{ $$ = new AstLte	($2,$1,$3); } 	|	expr '?' expr ':' expr		{ $$ = new AstCond($2,$1,$3,$5); } 	|	expr yP_MINUSGT expr		{ $$ = new AstLogIf	($2,$1,$3); } 	|	expr yP_LOGIFF expr		{ $$ = new AstLogIff	($2,$1,$3); } 	|	yaINTNUM				{ $$ = new AstConst($<fl>1,*$1); } 	|	yaFLOATNUM				{ $$ = new AstConst($<fl>1,AstConst::RealDouble(),$1); } 	|	strAsIntIgnore			{ $$ = $1; } 	|	'{' constExpr '{' cateList '}' '}'	{ $$ = new AstReplicate($1,$4,$2); } 	|	function_subroutine_callNoMethod	{ $$ = $1; } 	|	'(' expr ')'		{ $$ = $2; } 	|	'_' '(' statePushVlg expr statePop ')'	{ $$ = $4; } 	|	casting_type yP_TICK '(' expr ')'	{ $$ = new AstCast($2,$4,$1); } 	|	ySIGNED	     yP_TICK '(' expr ')'	{ $$ = new AstSigned($1,$4); } 	|	yUNSIGNED    yP_TICK '(' expr ')'	{ $$ = new AstUnsigned($1,$4); } 	|	exprOkLvalue				{ $$ = $1; } 	// {copied}
	;

exprOkLvalue:		// expression that's also OK to use as a variable_lvalue
		exprScope				{ $$ = $1; }
	//			// IEEE: concatenation/constant_concatenation
	|	'{' cateList '}'			{ $$ = $2; }
	//			// IEEE: assignment_pattern_expression
	//			// IEEE: [ assignment_pattern_expression_type ] == [ ps_type_id /ps_paremeter_id]
	//			// We allow more here than the spec requires
	//UNSUP	exprScope assignment_pattern		{ UNSUP }
	//UNSUP	data_type assignment_pattern		{ UNSUP }
	//UNSUP	assignment_pattern			{ UNSUP }
	//
	//UNSUP	streaming_concatenation			{ UNSUP }
	;

exprScope:		// scope and variable for use to inside an expression
	// 			// Here we've split method_call_root | implicit_class_handle | class_scope | package_scope
	//			// from the object being called and let expr's "." deal with resolving it.
	//
	//			// IEEE: [ implicit_class_handle . | class_scope | package_scope ] hierarchical_identifier select
	//			// Or method_call_body without parenthesis
	//			// See also varRefClassBit, which is the non-expr version of most of this
	//UNSUP	yTHIS					{ UNSUP }
		idClassSel				{ $$ = $1; }
	//UNSUP: idArrayed instead of idClassSel
	//UNSUP	package_scopeIdFollows idArrayed	{ UNSUP }
	//UNSUP	class_scopeIdFollows idArrayed		{ UNSUP }
	//UNSUP	expr '.' idArrayed			{ UNSUP }
	//			// expr below must be a "yTHIS"
	//UNSUP	expr '.' ySUPER			{ UNSUP }
	//			// Part of implicit_class_handle
	//UNSUP	ySUPER					{ UNSUP }
	;

// Psl excludes {}'s by lexer converting to different token
exprPsl:
		expr					{ $$ = $1; }
	;

// PLI calls exclude "" as integers, they're strings
// For $c("foo","bar") we want "bar" as a string, not a Verilog integer.
exprStrText:
		exprNoStr				{ $$ = $1; }
	|	strAsText				{ $$ = $1; }
	;

cStrList:
		exprStrText				{ $$ = $1; }
	|	exprStrText ',' cStrList		{ $$ = $1;$1->addNext($3); }
	;

cateList:
	//			// Not just 'expr' to prevent conflict via stream_concOrExprOrType
		stream_expression			{ $$ = $1; }
	|	cateList ',' stream_expression		{ $$ = new AstConcat($2,$1,$3); }
	;

exprList:
		expr					{ $$ = $1; }
	|	exprList ',' expr			{ $$ = $1;$1->addNext($3); }
	;

commaEListE:
		/* empty */				{ $$ = NULL; }
	|	',' exprList				{ $$ = $2; }
	;

vrdList:
		idClassSel				{ $$ = $1; }
	|	vrdList ',' idClassSel			{ $$ = $1;$1->addNext($3); }
	;

commaVRDListE:
		/* empty */				{ $$ = NULL; }
	|	',' vrdList				{ $$ = $2; }
	;

argsExprList:		// IEEE: part of list_of_arguments (used where ,, isn't legal)
		expr					{ $$ = $1; }
	|	argsExprList ',' expr			{ $$ = $1->addNext($3); }
	;

stream_expression:	// ==IEEE: stream_expression
	//			// IEEE: array_range_expression expanded below
		expr					{ $$ = $1; }
	//UNSUP	expr yWITH__BRA '[' expr ']'		{ UNSUP }
	//UNSUP	expr yWITH__BRA '[' expr ':' expr ']'	{ UNSUP }
	//UNSUP	expr yWITH__BRA '[' expr yP_PLUSCOLON  expr ']'	{ UNSUP }
	//UNSUP	expr yWITH__BRA '[' expr yP_MINUSCOLON expr ']'	{ UNSUP }
	;

//************************************************
// Gate declarations

gateDecl:
		yBUF    delayE gateBufList ';'		{ $$ = $3; }
	|	yBUFIF0 delayE gateBufif0List ';'	{ $$ = $3; }
	|	yBUFIF1 delayE gateBufif1List ';'	{ $$ = $3; }
	|	yNOT    delayE gateNotList ';'		{ $$ = $3; }
	|	yNOTIF0 delayE gateNotif0List ';'	{ $$ = $3; }
	|	yNOTIF1 delayE gateNotif1List ';'	{ $$ = $3; }
	|	yAND  delayE gateAndList ';'		{ $$ = $3; }
	|	yNAND delayE gateNandList ';'		{ $$ = $3; }
	|	yOR   delayE gateOrList ';'		{ $$ = $3; }
	|	yNOR  delayE gateNorList ';'		{ $$ = $3; }
	|	yXOR  delayE gateXorList ';'		{ $$ = $3; }
	|	yXNOR delayE gateXnorList ';'		{ $$ = $3; }
	|	yPULLUP delayE gatePullupList ';'	{ $$ = $3; }
	|	yPULLDOWN delayE gatePulldownList ';'	{ $$ = $3; }
	//
	|	yTRAN delayE gateUnsupList ';'		{ $$ = $3; GATEUNSUP($3,"tran"); } // Unsupported
	|	yNMOS delayE gateUnsupList ';'		{ $$ = $3; GATEUNSUP($3,"nmos"); } // Unsupported
	|	yPMOS delayE gateUnsupList ';'		{ $$ = $3; GATEUNSUP($3,"pmos"); } // Unsupported
	|	yRCMOS delayE gateUnsupList ';'		{ $$ = $3; GATEUNSUP($3,"rcmos"); } // Unsupported
	|	yCMOS delayE gateUnsupList ';'		{ $$ = $3; GATEUNSUP($3,"cmos"); } // Unsupported
	|	yRNMOS delayE gateUnsupList ';'		{ $$ = $3; GATEUNSUP($3,"rmos"); } // Unsupported
	|	yRPMOS delayE gateUnsupList ';'		{ $$ = $3; GATEUNSUP($3,"pmos"); } // Unsupported
	|	yRTRAN delayE gateUnsupList ';'		{ $$ = $3; GATEUNSUP($3,"rtran"); } // Unsupported
	|	yRTRANIF0 delayE gateUnsupList ';'	{ $$ = $3; GATEUNSUP($3,"rtranif0"); } // Unsupported
	|	yRTRANIF1 delayE gateUnsupList ';'	{ $$ = $3; GATEUNSUP($3,"rtranif1"); } // Unsupported
	|	yTRANIF0 delayE gateUnsupList ';'	{ $$ = $3; GATEUNSUP($3,"tranif0"); } // Unsupported
	|	yTRANIF1 delayE gateUnsupList ';'	{ $$ = $3; GATEUNSUP($3,"tranif1"); } // Unsupported
	;

gateBufList:
		gateBuf 				{ $$ = $1; }
	|	gateBufList ',' gateBuf			{ $$ = $1->addNext($3); }
	;
gateBufif0List:
		gateBufif0 				{ $$ = $1; }
	|	gateBufif0List ',' gateBufif0		{ $$ = $1->addNext($3); }
	;
gateBufif1List:
		gateBufif1 				{ $$ = $1; }
	|	gateBufif1List ',' gateBufif1		{ $$ = $1->addNext($3); }
	;
gateNotList:
		gateNot 				{ $$ = $1; }
	|	gateNotList ',' gateNot			{ $$ = $1->addNext($3); }
	;
gateNotif0List:
		gateNotif0 				{ $$ = $1; }
	|	gateNotif0List ',' gateNotif0		{ $$ = $1->addNext($3); }
	;
gateNotif1List:
		gateNotif1 				{ $$ = $1; }
	|	gateNotif1List ',' gateNotif1		{ $$ = $1->addNext($3); }
	;
gateAndList:
		gateAnd 				{ $$ = $1; }
	|	gateAndList ',' gateAnd			{ $$ = $1->addNext($3); }
	;
gateNandList:
		gateNand 				{ $$ = $1; }
	|	gateNandList ',' gateNand		{ $$ = $1->addNext($3); }
	;
gateOrList:
		gateOr 					{ $$ = $1; }
	|	gateOrList ',' gateOr			{ $$ = $1->addNext($3); }
	;
gateNorList:
		gateNor 				{ $$ = $1; }
	|	gateNorList ',' gateNor			{ $$ = $1->addNext($3); }
	;
gateXorList:
		gateXor 				{ $$ = $1; }
	|	gateXorList ',' gateXor			{ $$ = $1->addNext($3); }
	;
gateXnorList:
		gateXnor 				{ $$ = $1; }
	|	gateXnorList ',' gateXnor		{ $$ = $1->addNext($3); }
	;
gatePullupList:
		gatePullup 				{ $$ = $1; }
	|	gatePullupList ',' gatePullup		{ $$ = $1->addNext($3); }
	;
gatePulldownList:
		gatePulldown 				{ $$ = $1; }
	|	gatePulldownList ',' gatePulldown	{ $$ = $1->addNext($3); }
	;
gateUnsupList:
		gateUnsup 				{ $$ = $1; }
	|	gateUnsupList ',' gateUnsup		{ $$ = $1->addNext($3); }
	;

gateBuf:
		gateIdE instRangeE '(' variable_lvalue ',' expr ')'
			{ $$ = new AstAssignW ($3,$4,$6); }
	;
gateBufif0:
		gateIdE instRangeE '(' variable_lvalue ',' expr ',' expr ')'
			{ $$ = new AstAssignW ($3,$4,new AstBufIf1($3,new AstNot($3,$8),$6)); }
	;
gateBufif1:
		gateIdE instRangeE '(' variable_lvalue ',' expr ',' expr ')'
			{ $$ = new AstAssignW ($3,$4,new AstBufIf1($3,$8,$6)); }
	;
gateNot:
		gateIdE instRangeE '(' variable_lvalue ',' expr ')'
			{ $$ = new AstAssignW ($3,$4,new AstNot($5,$6)); }
	;
gateNotif0:
		gateIdE instRangeE '(' variable_lvalue ',' expr ',' expr ')'
			{ $$ = new AstAssignW ($3,$4,new AstBufIf1($3,new AstNot($3,$8), new AstNot($3, $6))); }
	;
gateNotif1:
		gateIdE instRangeE '(' variable_lvalue ',' expr ',' expr ')'
			{ $$ = new AstAssignW ($3,$4,new AstBufIf1($3,$8, new AstNot($3,$6))); }
	;
gateAnd:
		gateIdE instRangeE '(' variable_lvalue ',' gateAndPinList ')'
			{ $$ = new AstAssignW ($3,$4,$6); }
	;
gateNand:
	 	gateIdE instRangeE '(' variable_lvalue ',' gateAndPinList ')'
			{ $$ = new AstAssignW ($3,$4,new AstNot($5,$6)); }
	;
gateOr:
		gateIdE instRangeE '(' variable_lvalue ',' gateOrPinList ')'
			{ $$ = new AstAssignW ($3,$4,$6); }
	;
gateNor:
		gateIdE instRangeE '(' variable_lvalue ',' gateOrPinList ')'
			{ $$ = new AstAssignW ($3,$4,new AstNot($5,$6)); }
	;
gateXor:
		gateIdE instRangeE '(' variable_lvalue ',' gateXorPinList ')'
			{ $$ = new AstAssignW ($3,$4,$6); }
	;
gateXnor:
		gateIdE instRangeE '(' variable_lvalue ',' gateXorPinList ')'
			{ $$ = new AstAssignW ($3,$4,new AstNot($5,$6)); }
	;
gatePullup:
		gateIdE instRangeE '(' variable_lvalue ')'	{ $$ = new AstPull ($3, $4, true); }
	;
gatePulldown:
		gateIdE instRangeE '(' variable_lvalue ')'	{ $$ = new AstPull ($3, $4, false); }
	;
gateUnsup:
		gateIdE instRangeE '(' gateUnsupPinList ')'	{ $$ = new AstImplicit ($3,$4); }
	;

gateIdE:
		/*empty*/				{}
	|	id					{}
	;

gateAndPinList:
		expr 					{ $$ = $1; }
	|	gateAndPinList ',' expr			{ $$ = new AstAnd($2,$1,$3); }
	;
gateOrPinList:
		expr 					{ $$ = $1; }
	|	gateOrPinList ',' expr			{ $$ = new AstOr($2,$1,$3); }
	;
gateXorPinList:
		expr 					{ $$ = $1; }
	|	gateXorPinList ',' expr			{ $$ = new AstXor($2,$1,$3); }
	;
gateUnsupPinList:
		expr 					{ $$ = $1; }
	|	gateUnsupPinList ',' expr		{ $$ = $1->addNext($3); }
	;

strengthSpecE:			// IEEE: drive_strength + pullup_strength + pulldown_strength + charge_strength - plus empty
		/* empty */				{ }
	//UNSUP	strengthSpec				{ }
	;

//************************************************
// Tables

table:		// IEEE: combinational_body + sequential_body
		yTABLE tableEntryList yENDTABLE		{ $$ = new AstUdpTable($1,$2); }
	;

tableEntryList:	// IEEE: { combinational_entry | sequential_entry }
		tableEntry 				{ $$ = $1; }
	|	tableEntryList tableEntry		{ $$ = $1->addNext($2); }
	;

tableEntry:	// IEEE: combinational_entry + sequential_entry
		yaTABLELINE				{ $$ = new AstUdpTableLine($<fl>1,*$1); }
	|	error					{ $$ = NULL; }
	;

//************************************************
// Specify

specify_block:		// ==IEEE: specify_block
		ySPECIFY specifyJunkList yENDSPECIFY	{ $$ = NULL; }
	|	ySPECIFY yENDSPECIFY			{ $$ = NULL; }
	;

specifyJunkList:
		specifyJunk 				{ } /* ignored */
	|	specifyJunkList specifyJunk		{ } /* ignored */
	;

specifyJunk:
			 '!' { }	| '#' { }	| '%' { }	| '&' { }	| '(' { }	| ')' { }	| '*' { }	| '+' { }	| ',' { }	| '-' { }	| '.' { }	| '/' { }	| ':' { }	| ';' { }	| '<' { }	| '=' { }	| '>' { }	| '?' { }	| '@' { }	| '[' { }	| ']' { }	| '^' { }	| '{' { }	| '|' { }	| '}' { }	| '~' { }	| yALWAYS { }	| yAND { }	| yASSERT { }	| yASSIGN { }	| yAUTOMATIC { }	| yBEGIN { }	| yBIT { }	| yBREAK { }	| yBUF { }	| yBUFIF0 { }	| yBUFIF1 { }	| yBYTE { }	| yCASE { }	| yCASEX { }	| yCASEZ { }	| yCHANDLE { }	| yCLOCKING { }	| yCMOS { }	| yCONST__ETC { }	| yCONST__LEX { }	| yCONTEXT { }	| yCONTINUE { }	| yCOVER { }	| yDEFAULT { }	| yDEFPARAM { }	| yDISABLE { }	| yDO { }	| yD_BITS { }	| yD_BITSTOREAL { }	| yD_C { }	| yD_CEIL { }	| yD_CLOG2 { }	| yD_COUNTONES { }	| yD_DISPLAY { }	| yD_ERROR { }	| yD_EXP { }	| yD_FATAL { }	| yD_FCLOSE { }	| yD_FDISPLAY { }	| yD_FEOF { }	| yD_FFLUSH { }	| yD_FGETC { }	| yD_FGETS { }	| yD_FINISH { }	| yD_FLOOR { }	| yD_FOPEN { }	| yD_FSCANF { }	| yD_FWRITE { }	| yD_INFO { }	| yD_ISUNKNOWN { }	| yD_ITOR { }	| yD_LN { }	| yD_LOG10 { }	| yD_ONEHOT { }	| yD_ONEHOT0 { }	| yD_POW { }	| yD_RANDOM { }	| yD_READMEMB { }	| yD_READMEMH { }	| yD_REALTIME { }	| yD_REALTOBITS { }	| yD_RTOI { }	| yD_SFORMAT { }	| yD_SIGNED { }	| yD_SQRT { }	| yD_SSCANF { }	| yD_STIME { }	| yD_STOP { }	| yD_SWRITE { }	| yD_SYSTEM { }	| yD_TESTPLUSARGS { }	| yD_TIME { }	| yD_UNIT { }	| yD_UNSIGNED { }	| yD_VALUEPLUSARGS { }	| yD_WARNING { }	| yD_WRITE { }	| yEDGE { }	| yELSE { }	| yEND { }	| yENDCASE { }	| yENDCLOCKING { }	| yENDFUNCTION { }	| yENDGENERATE { }	| yENDMODULE { }	| yENDPACKAGE { }	| yENDPRIMITIVE { }	| yENDPROGRAM { }	| yENDPROPERTY { }	| yENDTABLE { }	| yENDTASK { }	| yENUM { }	| yEXPORT { }	| yFINAL { }	| yFOR { }	| yFOREVER { }	| yFUNCTION { }	| yGENERATE { }	| yGENVAR { }	| yGLOBAL__CLOCKING { }	| yGLOBAL__LEX { }	| yIF { }	| yIFF { }	| yIMPORT { }	| yINITIAL { }	| yINOUT { }	| yINPUT { }	| yINT { }	| yINTEGER { }	| yLOCALPARAM { }	| yLOGIC { }	| yLONGINT { }	| yMODULE { }	| yNAND { }	| yNEGEDGE { }	| yNMOS { }	| yNOR { }	| yNOT { }	| yNOTIF0 { }	| yNOTIF1 { }	| yOR { }	| yOUTPUT { }	| yPACKAGE { }	| yPARAMETER { }	| yPMOS { }	| yPOSEDGE { }	| yPRIMITIVE { }	| yPRIORITY { }	| yPROGRAM { }	| yPROPERTY { }	| yPSL { }	| yPSL_ASSERT { }	| yPSL_BRA { }	| yPSL_CLOCK { }	| yPSL_COVER { }	| yPSL_KET { }	| yPSL_REPORT { }	| yPULLDOWN { }	| yPULLUP { }	| yPURE { }	| yP_ANDAND { }	| yP_ANDANDAND { }	| yP_ANDEQ { }	| yP_ASTGT { }	| yP_ATAT { }	| yP_BRAEQ { }	| yP_BRAMINUSGT { }	| yP_BRASTAR { }	| yP_CASEEQUAL { }	| yP_CASENOTEQUAL { }	| yP_COLONCOLON { }	| yP_COLONDIV { }	| yP_COLONEQ { }	| yP_DIVEQ { }	| yP_DOTSTAR { }	| yP_EQGT { }	| yP_EQUAL { }	| yP_GTE { }	| yP_LOGIFF { }	| yP_LTE { }	| yP_MINUSCOLON { }	| yP_MINUSEQ { }	| yP_MINUSGT { }	| yP_MINUSGTGT { }	| yP_MINUSMINUS { }	| yP_MODEQ { }	| yP_NAND { }	| yP_NOR { }	| yP_NOTEQUAL { }	| yP_OREQ { }	| yP_OREQGT { }	| yP_ORMINUSGT { }	| yP_OROR { }	| yP_PLUSCOLON { }	| yP_PLUSEQ { }	| yP_PLUSPLUS { }	| yP_POUNDPOUND { }	| yP_POW { }	| yP_SLEFT { }	| yP_SLEFTEQ { }	| yP_SRIGHT { }	| yP_SRIGHTEQ { }	| yP_SSRIGHT { }	| yP_SSRIGHTEQ { }	| yP_TICK { }	| yP_TICKBRA { }	| yP_TIMESEQ { }	| yP_WILDEQUAL { }	| yP_WILDNOTEQUAL { }	| yP_XNOR { }	| yP_XOREQ { }	| yRCMOS { }	| yREAL { }	| yREALTIME { }	| yREG { }	| yREPEAT { }	| yRETURN { }	| yRNMOS { }	| yRPMOS { }	| yRTRAN { }	| yRTRANIF0 { }	| yRTRANIF1 { }	| ySCALARED { }	| ySHORTINT { }	| ySIGNED { }	| ySPECPARAM { }	| ySTATIC { }	| ySTRING { }	| ySUPPLY0 { }	| ySUPPLY1 { }	| yTABLE { }	| yTASK { }	| yTIME { }	| yTIMEPRECISION { }	| yTIMEUNIT { }	| yTRAN { }	| yTRANIF0 { }	| yTRANIF1 { }	| yTRI { }	| yTRUE { }	| yTYPEDEF { }	| yUNIQUE { }	| yUNIQUE0 { }	| yUNSIGNED { }	| yVAR { }	| yVECTORED { }	| yVLT_COVERAGE_OFF { }	| yVLT_D_FILE { }	| yVLT_D_LINES { }	| yVLT_D_MSG { }	| yVLT_LINT_OFF { }	| yVLT_TRACING_OFF { }	| yVL_CLOCK { }	| yVL_CLOCK_ENABLE { }	| yVL_COVERAGE_BLOCK_OFF { }	| yVL_FULL_CASE { }	| yVL_INLINE_MODULE { }	| yVL_ISOLATE_ASSIGNMENTS { }	| yVL_NO_INLINE_MODULE { }	| yVL_NO_INLINE_TASK { }	| yVL_PARALLEL_CASE { }	| yVL_PUBLIC { }	| yVL_PUBLIC_FLAT { }	| yVL_PUBLIC_FLAT_RD { }	| yVL_PUBLIC_FLAT_RW { }	| yVL_PUBLIC_MODULE { }	| yVL_SC_BV { }	| yVL_SFORMAT { }	| yVOID { }	| yWHILE { }	| yWIRE { }	| yWREAL { }	| yXNOR { }	| yXOR { }	| yaD_DPI { }	| yaD_IGNORE { }	| yaFLOATNUM { }	| yaID__ETC { }	| yaID__LEX { }	| yaID__aPACKAGE { }	| yaID__aTYPE { }	| yaINTNUM { }	| yaSCCTOR { }	| yaSCDTOR { }	| yaSCHDR { }	| yaSCIMP { }	| yaSCIMPH { }	| yaSCINT { }	| yaSTRING { }	| yaSTRING__IGNORE { }	| yaTABLELINE { }	| yaTIMENUM { }	| yaTIMINGSPEC { }
	|	ySPECIFY specifyJunk yENDSPECIFY	{ }
	|	error {}
	;

specparam_declaration:		// ==IEEE: specparam_declaration
		ySPECPARAM junkToSemiList ';'		{ $$ = NULL; }
	;

junkToSemiList:
		junkToSemi 				{ } /* ignored */
	|	junkToSemiList junkToSemi		{ } /* ignored */
 	;

junkToSemi:
			 '!' { }	| '#' { }	| '%' { }	| '&' { }	| '(' { }	| ')' { }	| '*' { }	| '+' { }	| ',' { }	| '-' { }	| '.' { }	| '/' { }	| ':' { }	| '<' { }	| '=' { }	| '>' { }	| '?' { }	| '@' { }	| '[' { }	| ']' { }	| '^' { }	| '{' { }	| '|' { }	| '}' { }	| '~' { }	| yALWAYS { }	| yAND { }	| yASSERT { }	| yASSIGN { }	| yAUTOMATIC { }	| yBEGIN { }	| yBIT { }	| yBREAK { }	| yBUF { }	| yBUFIF0 { }	| yBUFIF1 { }	| yBYTE { }	| yCASE { }	| yCASEX { }	| yCASEZ { }	| yCHANDLE { }	| yCLOCKING { }	| yCMOS { }	| yCONST__ETC { }	| yCONST__LEX { }	| yCONTEXT { }	| yCONTINUE { }	| yCOVER { }	| yDEFAULT { }	| yDEFPARAM { }	| yDISABLE { }	| yDO { }	| yD_BITS { }	| yD_BITSTOREAL { }	| yD_C { }	| yD_CEIL { }	| yD_CLOG2 { }	| yD_COUNTONES { }	| yD_DISPLAY { }	| yD_ERROR { }	| yD_EXP { }	| yD_FATAL { }	| yD_FCLOSE { }	| yD_FDISPLAY { }	| yD_FEOF { }	| yD_FFLUSH { }	| yD_FGETC { }	| yD_FGETS { }	| yD_FINISH { }	| yD_FLOOR { }	| yD_FOPEN { }	| yD_FSCANF { }	| yD_FWRITE { }	| yD_INFO { }	| yD_ISUNKNOWN { }	| yD_ITOR { }	| yD_LN { }	| yD_LOG10 { }	| yD_ONEHOT { }	| yD_ONEHOT0 { }	| yD_POW { }	| yD_RANDOM { }	| yD_READMEMB { }	| yD_READMEMH { }	| yD_REALTIME { }	| yD_REALTOBITS { }	| yD_RTOI { }	| yD_SFORMAT { }	| yD_SIGNED { }	| yD_SQRT { }	| yD_SSCANF { }	| yD_STIME { }	| yD_STOP { }	| yD_SWRITE { }	| yD_SYSTEM { }	| yD_TESTPLUSARGS { }	| yD_TIME { }	| yD_UNIT { }	| yD_UNSIGNED { }	| yD_VALUEPLUSARGS { }	| yD_WARNING { }	| yD_WRITE { }	| yEDGE { }	| yELSE { }	| yEND { }	| yENDCASE { }	| yENDCLOCKING { }	| yENDFUNCTION { }	| yENDGENERATE { }	| yENDPACKAGE { }	| yENDPRIMITIVE { }	| yENDPROGRAM { }	| yENDPROPERTY { }	| yENDTABLE { }	| yENDTASK { }	| yENUM { }	| yEXPORT { }	| yFINAL { }	| yFOR { }	| yFOREVER { }	| yFUNCTION { }	| yGENERATE { }	| yGENVAR { }	| yGLOBAL__CLOCKING { }	| yGLOBAL__LEX { }	| yIF { }	| yIFF { }	| yIMPORT { }	| yINITIAL { }	| yINOUT { }	| yINPUT { }	| yINT { }	| yINTEGER { }	| yLOCALPARAM { }	| yLOGIC { }	| yLONGINT { }	| yMODULE { }	| yNAND { }	| yNEGEDGE { }	| yNMOS { }	| yNOR { }	| yNOT { }	| yNOTIF0 { }	| yNOTIF1 { }	| yOR { }	| yOUTPUT { }	| yPACKAGE { }	| yPARAMETER { }	| yPMOS { }	| yPOSEDGE { }	| yPRIMITIVE { }	| yPRIORITY { }	| yPROGRAM { }	| yPROPERTY { }	| yPSL { }	| yPSL_ASSERT { }	| yPSL_BRA { }	| yPSL_CLOCK { }	| yPSL_COVER { }	| yPSL_KET { }	| yPSL_REPORT { }	| yPULLDOWN { }	| yPULLUP { }	| yPURE { }	| yP_ANDAND { }	| yP_ANDANDAND { }	| yP_ANDEQ { }	| yP_ASTGT { }	| yP_ATAT { }	| yP_BRAEQ { }	| yP_BRAMINUSGT { }	| yP_BRASTAR { }	| yP_CASEEQUAL { }	| yP_CASENOTEQUAL { }	| yP_COLONCOLON { }	| yP_COLONDIV { }	| yP_COLONEQ { }	| yP_DIVEQ { }	| yP_DOTSTAR { }	| yP_EQGT { }	| yP_EQUAL { }	| yP_GTE { }	| yP_LOGIFF { }	| yP_LTE { }	| yP_MINUSCOLON { }	| yP_MINUSEQ { }	| yP_MINUSGT { }	| yP_MINUSGTGT { }	| yP_MINUSMINUS { }	| yP_MODEQ { }	| yP_NAND { }	| yP_NOR { }	| yP_NOTEQUAL { }	| yP_OREQ { }	| yP_OREQGT { }	| yP_ORMINUSGT { }	| yP_OROR { }	| yP_PLUSCOLON { }	| yP_PLUSEQ { }	| yP_PLUSPLUS { }	| yP_POUNDPOUND { }	| yP_POW { }	| yP_SLEFT { }	| yP_SLEFTEQ { }	| yP_SRIGHT { }	| yP_SRIGHTEQ { }	| yP_SSRIGHT { }	| yP_SSRIGHTEQ { }	| yP_TICK { }	| yP_TICKBRA { }	| yP_TIMESEQ { }	| yP_WILDEQUAL { }	| yP_WILDNOTEQUAL { }	| yP_XNOR { }	| yP_XOREQ { }	| yRCMOS { }	| yREAL { }	| yREALTIME { }	| yREG { }	| yREPEAT { }	| yRETURN { }	| yRNMOS { }	| yRPMOS { }	| yRTRAN { }	| yRTRANIF0 { }	| yRTRANIF1 { }	| ySCALARED { }	| ySHORTINT { }	| ySIGNED { }	| ySPECIFY { }	| ySPECPARAM { }	| ySTATIC { }	| ySTRING { }	| ySUPPLY0 { }	| ySUPPLY1 { }	| yTABLE { }	| yTASK { }	| yTIME { }	| yTIMEPRECISION { }	| yTIMEUNIT { }	| yTRAN { }	| yTRANIF0 { }	| yTRANIF1 { }	| yTRI { }	| yTRUE { }	| yTYPEDEF { }	| yUNIQUE { }	| yUNIQUE0 { }	| yUNSIGNED { }	| yVAR { }	| yVECTORED { }	| yVLT_COVERAGE_OFF { }	| yVLT_D_FILE { }	| yVLT_D_LINES { }	| yVLT_D_MSG { }	| yVLT_LINT_OFF { }	| yVLT_TRACING_OFF { }	| yVL_CLOCK { }	| yVL_CLOCK_ENABLE { }	| yVL_COVERAGE_BLOCK_OFF { }	| yVL_FULL_CASE { }	| yVL_INLINE_MODULE { }	| yVL_ISOLATE_ASSIGNMENTS { }	| yVL_NO_INLINE_MODULE { }	| yVL_NO_INLINE_TASK { }	| yVL_PARALLEL_CASE { }	| yVL_PUBLIC { }	| yVL_PUBLIC_FLAT { }	| yVL_PUBLIC_FLAT_RD { }	| yVL_PUBLIC_FLAT_RW { }	| yVL_PUBLIC_MODULE { }	| yVL_SC_BV { }	| yVL_SFORMAT { }	| yVOID { }	| yWHILE { }	| yWIRE { }	| yWREAL { }	| yXNOR { }	| yXOR { }	| yaD_DPI { }	| yaD_IGNORE { }	| yaFLOATNUM { }	| yaID__ETC { }	| yaID__LEX { }	| yaID__aPACKAGE { }	| yaID__aTYPE { }	| yaINTNUM { }	| yaSCCTOR { }	| yaSCDTOR { }	| yaSCHDR { }	| yaSCIMP { }	| yaSCIMPH { }	| yaSCINT { }	| yaSTRING { }	| yaSTRING__IGNORE { }	| yaTABLELINE { }	| yaTIMENUM { }	| yaTIMINGSPEC { }
	|	error {}
	;

//************************************************
// IDs

id:
		yaID__ETC				{ $$ = $1; $<fl>$=$<fl>1; }
	;

idAny:			// Any kind of identifier
	//UNSUP	yaID__aCLASS				{ $$ = $1; $<fl>$=$<fl>1; }
	//UNSUP	yaID__aCOVERGROUP			{ $$ = $1; $<fl>$=$<fl>1; }
		yaID__aPACKAGE				{ $$ = $1; $<fl>$=$<fl>1; }
	|	yaID__aTYPE				{ $$ = $1; $<fl>$=$<fl>1; }
	|	yaID__ETC				{ $$ = $1; $<fl>$=$<fl>1; }
	;

idSVKwd:			// Warn about non-forward compatible Verilog 2001 code
	//			// yBIT, yBYTE won't work here as causes conflicts
		yDO					{ static string s = "do"   ; $$ = &s; ERRSVKWD($1,*$$); $<fl>$=$<fl>1; }
	|	yFINAL					{ static string s = "final"; $$ = &s; ERRSVKWD($1,*$$); $<fl>$=$<fl>1; }
	;

variable_lvalue:		// IEEE: variable_lvalue or net_lvalue
	//			// Note many variable_lvalue's must use exprOkLvalue when arbitrary expressions may also exist
		idClassSel				{ $$ = $1; }
	|	'{' variable_lvalueConcList '}'		{ $$ = $2; }
	//			// IEEE: [ assignment_pattern_expression_type ] assignment_pattern_variable_lvalue
	//			// We allow more assignment_pattern_expression_types then strictly required
	//UNSUP	data_type  yP_TICKBRA variable_lvalueList '}'	{ UNSUP }
	//UNSUP	idClassSel yP_TICKBRA variable_lvalueList '}'	{ UNSUP }
	//UNSUP	/**/       yP_TICKBRA variable_lvalueList '}'	{ UNSUP }
	//UNSUP	streaming_concatenation			{ UNSUP }
	;

variable_lvalueConcList:	// IEEE: part of variable_lvalue: '{' variable_lvalue { ',' variable_lvalue } '}'
		variable_lvalue					{ $$ = $1; }
	|	variable_lvalueConcList ',' variable_lvalue	{ $$ = new AstConcat($2,$1,$3); }
	;

// VarRef to a Memory
varRefMem:
		idDotted				{ $$ = new AstParseRef($1->fileline(), AstParseRefExp::PX_VAR_MEM, $1); }
	;

// VarRef to dotted, and/or arrayed, and/or bit-ranged variable
idClassSel:			// Misc Ref to dotted, and/or arrayed, and/or bit-ranged variable
		idDotted				{ $$ = new AstParseRef($1->fileline(), AstParseRefExp::PX_VAR_ANY, $1); }
	//			// IEEE: [ implicit_class_handle . | package_scope ] hierarchical_variable_identifier select
	//UNSUP	yTHIS '.' idDotted			{ UNSUP }
	//UNSUP	ySUPER '.' idDotted			{ UNSUP }
	//UNSUP	yTHIS '.' ySUPER '.' idDotted		{ UNSUP }
	//			// Expanded: package_scope idDotted
	//UNSUP	package_scopeIdFollows idDotted		{ UNSUP }
	;

idDotted:
	//UNSUP	yD_ROOT '.' idDottedMore		{ UNSUP }
		idDottedMore		 		{ $$ = $1; }
	;

idDottedMore:
		idArrayed 				{ $$ = $1; }
	|	idDotted '.' idArrayed	 		{ $$ = new AstDot($2,$1,$3); }
	;

// Single component of dotted path, maybe [#].
// Due to lookahead constraints, we can't know if [:] or [+:] are valid (last dotted part),
// we'll assume so and cleanup later.
// id below includes:
//	 enum_identifier
idArrayed:		// IEEE: id + select
		id						{ $$ = new AstText($<fl>1,*$1); }
	//			// IEEE: id + part_select_range/constant_part_select_range
	|	idArrayed '[' expr ']'				{ $$ = new AstSelBit($2,$1,$3); }  // Or AstArraySel, don't know yet.
	|	idArrayed '[' constExpr ':' constExpr ']'	{ $$ = new AstSelExtract($2,$1,$3,$5); }
	//			// IEEE: id + indexed_range/constant_indexed_range
	|	idArrayed '[' expr yP_PLUSCOLON  constExpr ']'	{ $$ = new AstSelPlus($2,$1,$3,$5); }
	|	idArrayed '[' expr yP_MINUSCOLON constExpr ']'	{ $$ = new AstSelMinus($2,$1,$3,$5); }
	;

// VarRef without any dots or vectorizaion
varRefBase:
		id					{ $$ = new AstVarRef($<fl>1,*$1,false);}
	;

// yaSTRING shouldn't be used directly, instead via an abstraction below
str:			// yaSTRING but with \{escapes} need decoded
		yaSTRING				{ $$ = PARSEP->newString(GRAMMARP->deQuote($<fl>1,*$1)); }
	;

strAsInt:
		yaSTRING				{ $$ = new AstConst($<fl>1,V3Number(V3Number::VerilogString(),$<fl>1,GRAMMARP->deQuote($<fl>1,*$1)));}
	;

strAsIntIgnore:		// strAsInt, but never matches for when expr shouldn't parse strings
		yaSTRING__IGNORE			{ $$ = NULL; yyerror("Impossible token"); }
	;

strAsText:
		yaSTRING				{ $$ = GRAMMARP->createTextQuoted($<fl>1,*$1);}
	;

endLabelE:
		/* empty */				{ $$ = NULL; $<fl>$=NULL; }
	|	':' idAny				{ $$ = $2; $<fl>$=$<fl>2; }
	//UNSUP	':' yNEW__ETC				{ $$ = $2; $<fl>$=$<fl>2; }
	;

//************************************************
// Clocking

clocking_declaration:		// IEEE: clocking_declaration  (INCOMPLETE)
		yDEFAULT yCLOCKING '@' '(' senitemEdge ')' ';' yENDCLOCKING
			{ $$ = new AstClocking($1, $5, NULL); }
	//UNSUP: Vastly simplified grammar
	;

//************************************************
// Asserts

labeledStmt:
		immediate_assert_statement		{ $$ = $1; }
	;

concurrent_assertion_item:	// IEEE: concurrent_assertion_item
		concurrent_assertion_statement		{ $$ = $1; }
	|	id/*block_identifier*/ ':' concurrent_assertion_statement	{ $$ = new AstBegin($2,*$1,$3); }
	;

concurrent_assertion_statement:	// ==IEEE: concurrent_assertion_statement
	//UNSUP: assert/assume
	//				// IEEE: cover_property_statement
		yCOVER yPROPERTY '(' property_spec ')' stmtBlock	{ $$ = new AstPslCover($1,$4,$6); }
	;

property_spec:			// IEEE: property_spec
	//UNSUP: This rule has been super-specialized to what is supported now
		'@' '(' senitemEdge ')' yDISABLE yIFF '(' expr ')' expr
			{ $$ = new AstPslClocked($1,$3,$8,$10); }
	|	'@' '(' senitemEdge ')' expr		{ $$ = new AstPslClocked($1,$3,NULL,$5); }
	|	yDISABLE yIFF '(' expr ')' expr	 	{ $$ = new AstPslClocked($4->fileline(),NULL,$4,$6); }
	|	expr	 				{ $$ = new AstPslClocked($1->fileline(),NULL,NULL,$1); }
	;

immediate_assert_statement:	// ==IEEE: immediate_assert_statement
	//				// action_block expanded here, for compatibility with AstVAssert
		yASSERT '(' expr ')' stmtBlock %prec prLOWER_THAN_ELSE	{ $$ = new AstVAssert($1,$3,$5, GRAMMARP->createDisplayError($1)); }
	|	yASSERT '(' expr ')'           yELSE stmtBlock		{ $$ = new AstVAssert($1,$3,NULL,$6); }
	|	yASSERT '(' expr ')' stmtBlock yELSE stmtBlock		{ $$ = new AstVAssert($1,$3,$5,$7);   }
	;

//************************************************
// Covergroup

//**********************************************************************
// Randsequence

//**********************************************************************
// Class

//=========
// Package scoping - to traverse the symbol table properly, the final identifer
// must be included in the rules below.
// Each of these must end with {symsPackageDone | symsClassDone}

ps_id_etc:		// package_scope + general id
		package_scopeIdFollowsE id		{ }
	;

ps_type:		// IEEE: ps_parameter_identifier | ps_type_identifier
				// Even though we looked up the type and have a AstNode* to it,
				// we can't fully resolve it because it may have been just a forward definition.
		package_scopeIdFollowsE yaID__aTYPE	{ $$ = new AstRefDType($<fl>2, *$2); $$->castRefDType()->packagep($1); }
	;

//=== Below rules assume special scoping per above

package_scopeIdFollowsE:	// IEEE: [package_scope]
	//			// IMPORTANT: The lexer will parse the following ID to be in the found package
		/* empty */				{ $$ = NULL; }
	|	package_scopeIdFollows			{ $$ = $1; }
	;

package_scopeIdFollows:	// IEEE: package_scope
	//			// IMPORTANT: The lexer will parse the following ID to be in the found package
	//			//vv mid rule action needed otherwise we might not have NextId in time to parse the id token
		yD_UNIT        { SYMP->nextId(PARSEP->rootp()); }
	/*cont*/	yP_COLONCOLON	{ $$ = GRAMMARP->unitPackage($<fl>1); }
	|	yaID__aPACKAGE { SYMP->nextId($<scp>1); }
	/*cont*/	yP_COLONCOLON	{ $$ = $<scp>1->castPackage(); }
	;

//************************************************
// PSL Statements

pslStmt:
		yPSL pslDir  stateExitPsl		{ $$ = $2; }
	|	yPSL pslDecl stateExitPsl 		{ $$ = $2; }
	;

pslDir:
		id ':' pslDirOne			{ $$ = $3; }
	|	pslDirOne		       		{ $$ = $1; }
	;

pslDirOne:
		yPSL_ASSERT pslProp ';'				{ $$ = new AstPslAssert($1,$2); }
	|	yPSL_ASSERT pslProp yPSL_REPORT yaSTRING ';'	{ $$ = new AstPslAssert($1,$2,*$4); }
	|	yPSL_COVER  pslProp ';'				{ $$ = new AstPslCover($1,$2,NULL); }
	|	yPSL_COVER  pslProp yPSL_REPORT yaSTRING ';'	{ $$ = new AstPslCover($1,$2,NULL,*$4); }
	;

pslDecl:
		yDEFAULT yPSL_CLOCK '=' senitemEdge ';'		{ $$ = new AstPslDefClock($3, $4); }
	|	yDEFAULT yPSL_CLOCK '=' '(' senitemEdge ')' ';'	{ $$ = new AstPslDefClock($3, $5); }
	;

//************************************************
// PSL Properties, Sequences and SEREs
// Don't use '{' or '}'; in PSL they're yPSL_BRA and yPSL_KET to avoid expr concatenates

pslProp:
		pslSequence				{ $$ = $1; }
	|	pslSequence '@' %prec prPSLCLK '(' senitemEdge ')' { $$ = new AstPslClocked($2,$4,NULL,$1); }  // or pslSequence @ ...?
	;

pslSequence:
		yPSL_BRA pslSere yPSL_KET		{ $$ = $2; }
	;

pslSere:
		pslExpr					{ $$ = $1; }
	|	pslSequence				{ $$ = $1; }  // Sequence containing sequence
	;

// Undocumented PSL rule is that {} is always a SERE; concatenation is not allowed.
// This can be bypassed with the _(...) embedding of any arbitrary expression.
pslExpr:
		exprPsl					{ $$ = new AstPslBool($1->fileline(), $1); }
	|	yTRUE					{ $$ = new AstPslBool($1, new AstConst($1, AstConst::LogicTrue())); }
	;

//**********************************************************************
// VLT Files

vltItem:
		vltOffFront				{ V3Config::addIgnore($1,"*",0,0); }
	|	vltOffFront yVLT_D_FILE yaSTRING	{ V3Config::addIgnore($1,*$3,0,0); }
	|	vltOffFront yVLT_D_FILE yaSTRING yVLT_D_LINES yaINTNUM			{ V3Config::addIgnore($1,*$3,$5->toUInt(),$5->toUInt()+1); }
	|	vltOffFront yVLT_D_FILE yaSTRING yVLT_D_LINES yaINTNUM '-' yaINTNUM	{ V3Config::addIgnore($1,*$3,$5->toUInt(),$7->toUInt()+1); }
	;

vltOffFront:
		yVLT_COVERAGE_OFF			{ $$ = V3ErrorCode::I_COVERAGE; }
	|	yVLT_TRACING_OFF			{ $$ = V3ErrorCode::I_TRACING; }
	|	yVLT_LINT_OFF				{ $$ = V3ErrorCode::I_LINT; }
	|	yVLT_LINT_OFF yVLT_D_MSG yaID__ETC
			{ $$ = V3ErrorCode((*$3).c_str());
			  if ($$ == V3ErrorCode::EC_ERROR) { $1->v3error("Unknown Error Code: "<<*$3<<endl);  } }
	;

//**********************************************************************
%%

int V3ParseImp::bisonParse() {
    if (PARSEP->debugBison()>=9) yydebug = 1;
    return yyparse();
}

const char* V3ParseImp::tokenName(int token) {
#if YYDEBUG || YYERROR_VERBOSE
    if (token >= 255)
	return yytname[token-255];
    else {
	static char ch[2];  ch[0]=token; ch[1]='\0';
	return ch;
    }
#else
    return "";
#endif
}

void V3ParseImp::parserClear() {
    // Clear up any dynamic memory V3Parser required
    VARDTYPE(NULL);
}

AstNode* V3ParseGrammar::createSupplyExpr(FileLine* fileline, string name, int value) {
    FileLine* newfl = new FileLine (fileline);
    newfl->warnOff(V3ErrorCode::WIDTH, true);
    AstNode* nodep = new AstConst(newfl, V3Number(newfl));
    // Adding a NOT is less work than figuring out how wide to make it
    if (value) nodep = new AstNot(newfl, nodep);
    nodep = new AstAssignW(newfl, new AstVarRef(fileline, name, true),
			   nodep);
    return nodep;
}

AstNodeDType* V3ParseGrammar::createArray(AstNodeDType* basep, AstRange* rangep, bool isPacked) {
    // Split RANGE0-RANGE1-RANGE2 into ARRAYDTYPE0(ARRAYDTYPE1(ARRAYDTYPE2(BASICTYPE3),RANGE),RANGE)
    AstNodeDType* arrayp = basep;
    if (rangep) { // Maybe no range - return unmodified base type
	while (rangep->nextp()) rangep = rangep->nextp()->castRange();
	while (rangep) {
	    AstRange* prevp = rangep->backp()->castRange();
	    if (prevp) rangep->unlinkFrBack();
	    arrayp = new AstArrayDType(rangep->fileline(), arrayp, rangep, isPacked);
	    rangep = prevp;
	}
    }
    return arrayp;
}

AstVar* V3ParseGrammar::createVariable(FileLine* fileline, string name, AstRange* arrayp, AstNode* attrsp) {
    AstNodeDType* dtypep = GRAMMARP->m_varDTypep;
    UINFO(5,"  creVar "<<name<<"  decl="<<GRAMMARP->m_varDecl<<"  io="<<GRAMMARP->m_varIO<<"  dt="<<(dtypep?"set":"")<<endl);
    if (GRAMMARP->m_varIO == AstVarType::UNKNOWN
	&& GRAMMARP->m_varDecl == AstVarType::PORT) {
	// Just a port list with variable name (not v2k format); AstPort already created
	if (dtypep) fileline->v3error("Unsupported: Ranges ignored in port-lists");
	return NULL;
    }
    AstVarType type = GRAMMARP->m_varIO;
    if (!dtypep) {  // Created implicitly
	dtypep = new AstBasicDType(fileline, LOGIC_IMPLICIT);
    } else {  // May make new variables with same type, so clone
	dtypep = dtypep->cloneTree(false);
    }
    //UINFO(0,"CREVAR "<<fileline->ascii()<<" decl="<<GRAMMARP->m_varDecl.ascii()<<" io="<<GRAMMARP->m_varIO.ascii()<<endl);
    if (type == AstVarType::UNKNOWN
	|| (type == AstVarType::PORT && GRAMMARP->m_varDecl != AstVarType::UNKNOWN))
	type = GRAMMARP->m_varDecl;
    if (type == AstVarType::UNKNOWN) fileline->v3fatalSrc("Unknown signal type declared");
    if (type == AstVarType::GENVAR) {
	if (arrayp) fileline->v3error("Genvars may not be arrayed: "<<name);
    }

    // Split RANGE0-RANGE1-RANGE2 into ARRAYDTYPE0(ARRAYDTYPE1(ARRAYDTYPE2(BASICTYPE3),RANGE),RANGE)
    AstNodeDType* arrayDTypep = createArray(dtypep,arrayp,false);

    AstVar* nodep = new AstVar(fileline, type, name, arrayDTypep);
    nodep->addAttrsp(attrsp);
    if (GRAMMARP->m_varDecl != AstVarType::UNKNOWN) nodep->combineType(GRAMMARP->m_varDecl);
    if (GRAMMARP->m_varIO != AstVarType::UNKNOWN) nodep->combineType(GRAMMARP->m_varIO);

    if (GRAMMARP->m_varDecl == AstVarType::SUPPLY0) {
	nodep->addNext(V3ParseGrammar::createSupplyExpr(fileline, nodep->name(), 0));
    }
    if (GRAMMARP->m_varDecl == AstVarType::SUPPLY1) {
	nodep->addNext(V3ParseGrammar::createSupplyExpr(fileline, nodep->name(), 1));
    }
    // Clear any widths that got presumed by the ranging;
    // We need to autosize parameters and integers separately
    nodep->width(0,0);
    // Propagate from current module tracing state
    if (nodep->isGenVar() || nodep->isParam()) nodep->trace(false);
    else nodep->trace(v3Global.opt.trace() && nodep->fileline()->tracingOn());

    // Remember the last variable created, so we can attach attributes to it in later parsing
    GRAMMARP->m_varAttrp = nodep;
    return nodep;
}

string V3ParseGrammar::deQuote(FileLine* fileline, string text) {
    // Fix up the quoted strings the user put in, for example "\"" becomes "
    // Reverse is AstNode::quoteName(...)
    bool quoted = false;
    string newtext;
    unsigned char octal_val = 0;
    int octal_digits = 0;
    for (const char* cp=text.c_str(); *cp; ++cp) {
	if (quoted) {
	    if (isdigit(*cp)) {
		octal_val = octal_val*8 + (*cp-'0');
		if (++octal_digits == 3) {
		    octal_digits = 0;
		    quoted = false;
		    newtext += octal_val;
		}
	    } else {
		if (octal_digits) {
		    // Spec allows 1-3 digits
		    octal_digits = 0;
		    quoted = false;
		    newtext += octal_val;
		    --cp;  // Backup to reprocess terminating character as non-escaped
		    continue;
		}
		quoted = false;
		if (*cp == 'n') newtext += '\n';
		else if (*cp == 'a') newtext += '\a'; // SystemVerilog 3.1
		else if (*cp == 'f') newtext += '\f'; // SystemVerilog 3.1
		else if (*cp == 'r') newtext += '\r';
		else if (*cp == 't') newtext += '\t';
		else if (*cp == 'v') newtext += '\v'; // SystemVerilog 3.1
		else if (*cp == 'x' && isxdigit(cp[1]) && isxdigit(cp[2])) { // SystemVerilog 3.1
#define vl_decodexdigit(c) ((isdigit(c)?((c)-'0'):(tolower((c))-'a'+10)))
		    newtext += (char)(16*vl_decodexdigit(cp[1]) + vl_decodexdigit(cp[2]));
		    cp += 2;
		}
		else if (isalnum(*cp)) {
		    fileline->v3error("Unknown escape sequence: \\"<<*cp);
		    break;
		}
		else newtext += *cp;
	    }
	}
	else if (*cp == '\\') {
	    quoted = true;
	    octal_digits = 0;
	}
	else if (*cp != '"') {
	    newtext += *cp;
	}
    }
    return newtext;
}

//YACC = /kits/sources/bison-2.4.1/src/bison --report=lookahead
// --report=lookahead
// --report=itemset
// --graph
