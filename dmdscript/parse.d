 /* Digital Mars DMDScript source code.
 * Copyright (c) 2000-2002 by Chromium Communications
 * D version Copyright (c) 2004-2010 by Digital Mars
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 * written by Walter Bright
 * http://www.digitalmars.com
 *
 * D2 port by Dmitry Olshansky
 *
 * Upgrading to EcmaScript 5.1 by Carsten Bleser Rasmussen
 *
 * DMDScript is implemented in the D Programming Language,
 * http://www.digitalmars.com/d/
 *
 * For a C++ implementation of DMDScript, including COM support, see
 * http://www.digitalmars.com/dscript/cppscript.html
 */


module dmdscript.parse;

import dmdscript.script;
import dmdscript.lexer;
import dmdscript.functiondefinition;
import dmdscript.expression;
import dmdscript.statement;
import dmdscript.identifier;
import dmdscript.ir;
import dmdscript.errmsgs;
import dmdscript.text;

import std.stdio;

class Parser : Lexer
{
    uint flags;
    Expression last_exp;
    //  bool iseval;

    // Used to check that case statement is the first statement after
    // an switch statemet
    uint statement_count;
    uint switch_case_statement_count;
    // Scope depth
    int[] condition_block_depth;
    enum
    {
        normal          = 0,
        initial         = 1,

        allowIn         = 0,
        noIn            = 2,

        // Flag if we're in the for statement header, as
        // automatic semicolon insertion is suppressed inside it.
        inForHeader     = 4,
    }
    FunctionDefinition lastnamedfunc;


    this(d_string sourcename, d_string base, int useStringtable, bool iseval=false)
    {
        //writefln("Parser.this(base = '%s')", base);
        super(sourcename, base, useStringtable);
        this.iseval=iseval;
        condition_block_depth.length=1;
        nextToken();            // start up the scanner
    }

    ~this()
    {
        lastnamedfunc = null;
    }


    /**********************************************
     * Return !=0 on error, and fill in *perrinfo.
     */

    static int parseFunctionDefinition(out FunctionDefinition pfd,
                                       d_string params, d_string bdy, out ErrInfo perrinfo)
    {
        Identifier*[] parameters;
        TopStatement[] topstatements;
        FunctionDefinition fd = null;
        int result;


        scope Parser p = new Parser("anonymous", params, 0);
        scope Parser pbdy = new Parser("anonymous", bdy, 0);
        pbdy.first_command_in_block=true;
        pbdy.inside_function_block=true;
        // Parse FormalParameterList
        while(p.token.value != TOK.TOKeof)
        {
            if(p.token.value != TOK.TOKidentifier)
            {
                p.error(errmsgtbl[ERR_FPL_EXPECTED_IDENTIFIER], p.token.toText);
                goto Lreturn;
            }
            parameters ~= p.token.ident;
            p.nextToken();
            if(p.token.value == TOK.TOKcomma)
                p.nextToken();
            else if(p.token.value == TOK.TOKeof)
                break;
            else
            {
                p.error(errmsgtbl[ERR_FPL_EXPECTED_COMMA], p.token.toText);
                goto Lreturn;
            }
        }
        if(p.errinfo.message)
            goto Lreturn;

//        delete p;

        // Parse StatementList

        for(;; )
        {
            TopStatement ts;

            if(pbdy.token.value == TOK.TOKeof)
                break;
            ts = pbdy.parseStatement(true);
            topstatements ~= ts;
        }

        fd = new FunctionDefinition(0, 0, null, parameters, topstatements);
        fd.strict_mode=pbdy.use_strict;


      Lreturn:
        pfd = fd;
        perrinfo = p.errinfo;
        result = (p.errinfo.message !is null);
//        delete pbdy;
//        pbdy = null;
        return result;
    }

    /**********************************************
     * Return !=0 on error, and fill in *perrinfo.
     */

    bool parseProgram(out TopStatement[] topstatements, out ErrInfo perrinfo)
    {
        topstatements = parseTopStatements();
        check(TOK.TOKeof);
        //writef("parseProgram done\n");
        perrinfo = errinfo;
        //clearstack();
        return errinfo.message !is null;
    }

    TopStatement[] parseTopStatements()
    {
        TopStatement[] topstatements;
        TopStatement ts;
         // Enable the search for 'use strict';
        first_command_in_block=true;
        // writefln("parseTopStatements()");
        for(;; )
        {
            with(TOK) switch(token.value)
            {
            case TOKfunction:
                // Ecma Note 12
                // This check for function declaration inside block statement
                if ( condition_block_depth[$-1] > 0 ) {
                    error(errmsgtbl[ERR_FUNCTION_INSIDE_BLOCK]);
                }
                ts = parseFunction(0);
                topstatements ~= ts;
                break;

            case TOKeof:
                return topstatements;

            case TOKrbrace:
                return topstatements;

            default:
                ts = parseStatement(first_command_in_block);
                topstatements ~= ts;
                break;
            }
        }
        assert(0);
    }

    /***************************
     * flag:
     *	0	Function statement
     *	1	Function literal
     */

    TopStatement parseFunction(int flag)
    {
        Identifier* name;
        Identifier*[] parameters;
        TopStatement[] topstatements;
        FunctionDefinition f;
        Expression e = null;
        Loc loc;

        auto start_src=p;
        auto end_src=p;
        d_string _getsource() {
            return start_src[0..cast(size_t)((end_src-start_src))];
        }

        auto use_strict_save=use_strict;
        bool inside_function_block_save=inside_function_block;
        inside_function_block=true;
        scope(exit) {
            use_strict=use_strict_save;
            inside_function_block=inside_function_block_save;

        }
        loc = currentline;
        nextToken();
        name = null;

        if(token.value == TOK.TOKidentifier)
        {
            name = token.ident;
            // writeln("function ident=",token.toText);
            nextToken();

            if(!flag && token.value == TOK.TOKdot)
            {
                // Regard:
                //	function A.B() { }
                // as:
                //	A.B = function() { }
                // This is not ECMA, but a jscript feature

                e = new IdentifierExpression(loc, name);
                name = null;

                while(token.value == TOK.TOKdot)
                {
                    nextToken();
                    if(token.value == TOK.TOKidentifier)
                    {
                        e = new DotExp(loc, e, token.ident);
                        nextToken();
                    }
                    else
                    {
                        error(errmsgtbl[ERR_EXPECTED_IDENTIFIER_2PARAM], ".", token.toText);
                        break;
                    }
                }
            }
        }

        check(TOK.TOKlparen);
        if(token.value == TOK.TOKrparen)
            nextToken();
        else
        {
            for(;; )
            {
                if(token.value == TOK.TOKidentifier)
                {
                    parameters ~= token.ident;
                    //
                    // We run strict mode always here
                    // Reserved parameter name checks
                    //
                    if ( token.toText == TEXT_arguments ) {
                        error(errmsgtbl[ERR_ARGUMENTS_RESERVED], token.toText);
                    }
                    nextToken();
                    if(token.value == TOK.TOKcomma)
                    {
                        nextToken();
                        continue;
                    }
                    if(!check(TOK.TOKrparen))
                        break;
                } else {
                    error(ERR_EXPECTED_IDENTIFIER);
                }
                break;
            }
        }

        start_src=p;
        end_src=p;
        check(TOK.TOKlbrace);
        topstatements = parseTopStatements();
        end_src=p-Token.tochars[TOK.TOKrbrace].length;
        check(TOK.TOKrbrace);
        // Rewind to TOK.TOKrbrace


        f = new FunctionDefinition(loc, 0, name, parameters, topstatements);
        f.strict_mode=use_strict;
        f.isliteral = flag;
        f.source = _getsource();
        lastnamedfunc = f;

        //writef("parseFunction() done\n");
        if(!e) {
            return f;
        }
        // Construct:
        //	A.B = function() { }

        Expression e2 = new FunctionLiteral(loc, f);

        e = new AssignExp(loc, e, e2);

        Statement s = new ExpStatement(loc, e);

        return s;
    }

    /***************************
     * flag:
     *	false	Setter Function
     *	true	Getter Function
     */

    Expression parseSetGetter(Identifier* name, bool flag)
    {
        Identifier*[] parameters;
        TopStatement[] topstatements;
        FunctionDefinition f;
        Loc loc;

        loc = currentline;
//        nextToken();
//        name = null;

        // (<paramlist>) { <function body> }
        check(TOK.TOKlparen);
        if(token.value == TOK.TOKrparen)
            nextToken();
        else
        {
            for(;; )
            {
                if(token.value == TOK.TOKidentifier)
                {
                    parameters ~= token.ident;
                    //
                    // We run strict mode always here
                    // Reserved parameter name checks
                    //
                    if ( token.toText == TEXT_arguments ) {
                        error(errmsgtbl[ERR_ARGUMENTS_RESERVED], token.toText);
                    }
                    nextToken();
                    if(token.value == TOK.TOKcomma)
                    {
                        nextToken();
                        continue;
                    }
                    if(!check(TOK.TOKrparen))
                        break;
                } else {
                    error(ERR_EXPECTED_IDENTIFIER);
                }
                break;
            }
        }

        check(TOK.TOKlbrace);
        topstatements = parseTopStatements();
        check(TOK.TOKrbrace);
        // Rewind to TOK.TOKrbrace


        if (use_strict && iseval) {
            foreach(p;parameters) {
                if (p.toText == TEXT_eval) {
                    error(errmsgtbl[ERR_RESERVED_PARAMETER_NAME], p.toText);
                }
            }
        }
        f = new FunctionDefinition(loc, 0, name, parameters, topstatements);
        f.strict_mode=use_strict;
        f.isliteral = false;
        //lastnamedfunc = f;

        // Construct:
        //	A.B = function() { }

        Expression e  = new IdentifierExpression(loc, name);
        Expression e2 = new FunctionLiteral(loc, f);

        e = new AssignExp(loc, e, e2, true);

        //    Statement s = new ExpStatement(loc, e);

        return e;
    }

    /*****************************************
     */

    Statement parseStatement(bool first_call=false)
    {
        Statement s;
        Token *t;
        Loc loc;

        if ( !first_call ) first_command_in_block=false;
        //  writefln("parseStatement()=%d",condition_block_depth);
        statement_count++;
        loc = currentline;
        with(TOK) switch(token.value)
        {
        case TOKidentifier:
            if (use_strict) {
                //&& isKeyword(token.toText) ) {
                //               error(errmsgtbl[ERR_STATEMENT_EXPECTED], token.toText);
                auto ptok=token.toText in akeyword;
                if (ptok) {
                    goto Lerror;
                }

            }
        case TOKthis:
            first_command_in_block=false;
            // Need to look ahead to see if it is a declaration, label, or expression
            t = peek(&token);
            if(t.value == TOKcolon && token.value == TOKidentifier)
            {       // It's a label
                Identifier *ident;

                ident = token.ident;
                nextToken();
                nextToken();
                s = parseStatement(first_command_in_block);
                s = new LabelStatement(loc, ident, s);
            }
            else if(t.value == TOKassign ||
                    t.value == TOKdot ||
                    t.value == TOKlbracket)
            {
                Expression exp;

                exp = parseExpression();
                parseOptionalSemi();
                s = new ExpStatement(loc, exp);
                last_exp=exp;
            }
            else
            {
                Expression exp;

                exp = parseExpression(initial);
                parseOptionalSemi();
                s = new ExpStatement(loc, exp);
                last_exp=exp;
            }
            break;

        case TOKreal:
        case TOKstring:
        case TOKdelete:
        case TOKlparen:
        case TOKplusplus:
        case TOKminusminus:
        case TOKplus:
        case TOKminus:
        case TOKnot:
        case TOKtilde:
        case TOKtypeof:
        case TOKnull:
        case TOKnew:
        case TOKtrue:
        case TOKfalse:
        case TOKvoid:
        case TOKlbracket:
        { Expression exp;
          exp = parseExpression(initial);
          parseOptionalSemi();
          s = new ExpStatement(loc, exp);
          break; }
        case TOKregexp:
            if (iseval) {
                Expression exp;
                exp=parsePrimaryExp(0);
                s = new ExpStatement(loc, exp);
                nextToken();
            } else {
                error(errmsgtbl[ERR_STATEMENT_EXPECTED], token.toText);
                nextToken();
                s = null;
            }
            break;


/*
        case TOKlbracket:
        {   // Add to comply with test262 testcases
            Expression exp;
            exp = parseArrayLiteral();
            if ( token.value != TOKdot ) {
                 parseOptionalSemi();
            }
            s = new ExpStatement(loc, exp);
            break;
        }
*/
        case TOKvar:
        {
            Identifier *ident;
            Expression init;
            VarDeclaration v;
            VarStatement vs;

            first_command_in_block=false;

            vs = new VarStatement(loc);
            s = vs;

            nextToken();
            for(;; )
            {
                loc = currentline;

                if(token.value != TOKidentifier)
                {
                    error(errmsgtbl[ERR_EXPECTED_IDENTIFIER_PARAM], token.toText);
                    break;
                }
                ident = token.ident;
                init = null;
                nextToken();
                if(token.value == TOKassign)
                {
                    uint flags_save;

                    nextToken();
                    flags_save = flags;
                    flags &= ~initial;
                    init = parseAssignExp();
                    flags = flags_save;
                }
                v = new VarDeclaration(loc, ident, init);
                vs.vardecls ~= v;
                if(token.value != TOKcomma)
                    break;
                nextToken();
            }
            if(!(flags & inForHeader))
                parseOptionalSemi();
            break;
        }

        case TOKlbrace:
        { BlockStatement bs;

          nextToken();
          bs = new BlockStatement(loc);
          /*while(token.value != TOKrbrace)
          {
              if(token.value == TOKeof)
              {
                  error(ERR_UNTERMINATED_BLOCK);
                  break;
              }
              bs.statements ~= parseStatement();
          }*/
          bs.statements ~= parseTopStatements();
          s = bs;
          nextToken();

          // The following is to accommodate the jscript bug:
          //	if (i) {return(0);}; else ...
          /*if(token.value == TOKsemicolon)
              nextToken();*/

          break; }

        case TOKif:
        { Expression condition;
          Statement ifbody;
          Statement elsebody;

          nextToken();
          condition_block_depth[$-1]++;
          condition = parseParenExp();
          ifbody = parseStatement();
          condition_block_depth[$-1]--;
          if(token.value == TOKelse)
          {
              nextToken();
              condition_block_depth[$-1]++;
              elsebody = parseStatement();
              condition_block_depth[$-1]--;
          }
          else
              elsebody = null;
          s = new IfStatement(loc, condition, ifbody, elsebody);
          break; }

        case TOKswitch:
        { Expression condition;
          Statement bdy;


          nextToken();
          //   writefln("switch =%d",statement_count);
          switch_case_statement_count=statement_count;
          condition = parseParenExp();
          if ( token.value != TOKlbrace ) {
              error(errmsgtbl[ERR_EMPTY_SWITCH_CASE], token.toText);
          }
          bdy = parseStatement();
          s = new SwitchStatement(loc, condition, bdy);
          break; }

        case TOKcase:
        { Expression exp;

            //  writeln("case ",statement_count,":",switch_case_statement_count+2);
          if ( statement_count-2 > switch_case_statement_count ) {
              //             writeln("case should follow as the first statement after a switch");
              error(errmsgtbl[ERR_SWITCH_CASE_FIRST]);
          }
          switch_case_statement_count=uint.max-10;
          nextToken();
          exp = parseExpression();
          check(TOKcolon);
          s = new CaseStatement(loc, exp);
          break; }

        case TOKdefault:
            nextToken();
            check(TOKcolon);
            s = new DefaultStatement(loc);
            break;

        case TOKwhile:
        { Expression condition;
          Statement bdy;

          nextToken();
          condition = parseParenExp();

          condition_block_depth[$-1]++;
          bdy = parseStatement();
          condition_block_depth[$-1]--;

          s = new WhileStatement(loc, condition, bdy);
          break; }

        case TOKsemicolon:
            nextToken();
            s = new EmptyStatement(loc);
            break;

        case TOKdo:
        { Statement bdy;
          Expression condition;

          nextToken();
          condition_block_depth[$-1]++;
          bdy = parseStatement();
          condition_block_depth[$-1]--;
          check(TOKwhile);
          condition = parseParenExp();

		  //We do what most browsers now do, ie allow missing ';'
		  //like " do{ statement; }while(e) statement; " and that even w/o linebreak
		  if(token.value == TOKsemicolon)
			  nextToken();
          //parseOptionalSemi();
          s = new DoStatement(loc, bdy, condition);
          break; }

        case TOKfor:
        {
            Statement init;
            Statement bdy;

            nextToken();
            flags |= inForHeader;
            check(TOKlparen);
            if(token.value == TOKvar)
            {
                init = parseStatement();
            }
            else
            {
                Expression e;

                e = parseOptionalExpression(noIn);
                init = e ? new ExpStatement(loc, e) : null;
            }

            if(token.value == TOKsemicolon)
            {
                Expression condition;
                Expression increment;

                nextToken();
                condition = parseOptionalExpression();
                check(TOKsemicolon);
                increment = parseOptionalExpression();
                check(TOKrparen);
                flags &= ~inForHeader;

                condition_block_depth[$-1]++;
                bdy = parseStatement();
                condition_block_depth[$-1]--;

                s = new ForStatement(loc, init, condition, increment, bdy);
            }
            else if(token.value == TOKin)
            {
                Expression inexp;
                VarStatement vs;

                // Check that there's only one VarDeclaration
                // in init.
                if(init.st == d_statement.VARSTATEMENT)
                {
                    vs = cast(VarStatement)init;
                    if(vs.vardecls.length != 1)
                        error(errmsgtbl[ERR_TOO_MANY_IN_VARS], vs.vardecls.length);
                }

                nextToken();
                inexp = parseExpression();
                check(TOKrparen);
                flags &= ~inForHeader;

                condition_block_depth[$-1]++;
                bdy = parseStatement();
                condition_block_depth[$-1]--;

                s = new ForInStatement(loc, init, inexp, bdy);
            }
            else
            {
                error(errmsgtbl[ERR_IN_EXPECTED], token.toText);
                s = null;
            }
            break;
        }

        case TOKwith:
        { Expression exp;
          Statement bdy;

          nextToken();
          exp = parseParenExp();
          bdy = parseStatement();
          s = new WithStatement(loc, exp, bdy);
          break; }

        case TOKbreak:
        { Identifier *ident;
          nextToken();
          if(token.sawLineTerminator && token.value != TOKsemicolon)
          {         // Assume we saw a semicolon
              ident = null;
          }
          else
          {
              if(token.value == TOKidentifier)
              {
                  ident = token.ident;
                  nextToken();
              }
              else
                  ident = null;
              parseOptionalSemi();
          }
          s = new BreakStatement(loc, ident, last_exp, iseval);
          break; }

        case TOKcontinue:
        { Identifier *ident;

          nextToken();
          if(token.sawLineTerminator && token.value != TOKsemicolon)
          {         // Assume we saw a semicolon
              ident = null;
          }
          else
          {
              if(token.value == TOKidentifier)
              {
                  ident = token.ident;
                  nextToken();
              }
              else
                  ident = null;
              parseOptionalSemi();
          }
          s = new ContinueStatement(loc, ident);
          break; }

        case TOKgoto:
        { Identifier *ident;

          nextToken();
          if(token.value != TOKidentifier)
          {
              error(errmsgtbl[ERR_GOTO_LABEL_EXPECTED], token.toText);
              s = null;
              break;
          }
          ident = token.ident;
          nextToken();
          parseOptionalSemi();
          s = new GotoStatement(loc, ident);
          break; }

        case TOKreturn:
        { Expression exp;

          nextToken();
          if(token.sawLineTerminator && token.value != TOKsemicolon)
          {         // Assume we saw a semicolon
              s = new ReturnStatement(loc, null);
          }
          else
          {
              exp = parseOptionalExpression();
              parseOptionalSemi();
              s = new ReturnStatement(loc, exp);
          }
          break; }

        case TOKthrow:
        { Expression exp;

          nextToken();
          exp = parseExpression();
          parseOptionalSemi();
          s = new ThrowStatement(loc, exp);
          break; }

        case TOKtry:
        { Statement bdy;
          Identifier *catchident;
          Statement catchbody;
          Statement finalbody;

          nextToken();
          bdy = parseStatement();
          if(token.value == TOKcatch)
          {
              nextToken();
              check(TOKlparen);
              catchident = null;
              if(token.value == TOKidentifier)
                  catchident = token.ident;
              check(TOKidentifier);
              check(TOKrparen);
              catchbody = parseStatement();
          }
          else
          {
              catchident = null;
              catchbody = null;
          }

          if(token.value == TOKfinally)
          {
              nextToken();
              finalbody = parseStatement();
          }
          else
              finalbody = null;

          if(!catchbody && !finalbody)
          {
              error(ERR_TRY_CATCH_EXPECTED);
              s = null;
          }
          else
          {
              s = new TryStatement(loc, bdy, catchident, catchbody, finalbody);
          }
          break; }
        default:
        Lerror:
            error(errmsgtbl[ERR_STATEMENT_EXPECTED], token.toText);
            nextToken();
            s = null;
            break;
        }

        first_command_in_block=false;
        //   writefln("parseStatement() done");
        return s;
    }



    Expression parseOptionalExpression(uint flags = 0)
    {
        Expression e;

        if(token.value == TOK.TOKsemicolon || token.value == TOK.TOKrparen)
            e = null;
        else
            e = parseExpression(flags);
        return e;
    }

    // Follow ECMA 7.8.1 rules for inserting semicolons
    void parseOptionalSemi()
    {
        if(token.value != TOK.TOKeof &&
           token.value != TOK.TOKrbrace &&
           !(token.sawLineTerminator && (flags & inForHeader) == 0)
           )
            check(TOK.TOKsemicolon);
    }

    int check(TOK value)
    {
        if(token.value != value)
        {
            error(errmsgtbl[ERR_EXPECTED_GENERIC], token.toText, Token.toText(value));
            return 0;
        }
        nextToken();
        return 1;
    }

    /********************************* Expression Parser ***************************/


    Expression parseParenExp()
    {
        Expression e;

        check(TOK.TOKlparen);
        e = parseExpression();
        check(TOK.TOKrparen);
        return e;
    }

    Expression parsePrimaryExp(int innew)
    {
        Expression e;
        Loc loc;

        loc = currentline;
        with(TOK) switch(token.value)
        {
        case TOKthis:
            e = new ThisExpression(loc);
            nextToken();
            break;

        case TOKnull:
            e = new NullExpression(loc);
            nextToken();
            break;
        case TOKtrue:
            e = new BooleanExpression(loc, 1);
            nextToken();
            break;

        case TOKfalse:
            e = new BooleanExpression(loc, 0);
            nextToken();
            break;

        case TOKreal:
            e = new RealExpression(loc, token.realvalue);
            nextToken();
            break;

        case TOKstring:
            bool enable_strict=(first_command_in_block || !inside_function_block) && !use_strict && Lexer.strictToken(token);
            e = new StringExpression(loc, token.string, first_command_in_block);
            version(Ecmascript5) {
                if ( enable_strict ) {

                    use_strict=true;
                }
            }


            // first_command_in_block=false;
            token.string = null;        // release to gc
            nextToken();
            break;

        case TOKregexp:
            e = new RegExpLiteral(loc, token.string);
            token.string = null;        // release to gc
            nextToken();
            break;

        case TOKidentifier:
            e = new IdentifierExpression(loc, token.ident);
            token.ident = null;                 // release to gc
            nextToken();
            break;

        case TOKlparen:
            e = parseParenExp();
            break;

        case TOKlbracket:
            e = parseArrayLiteral();
            break;

        case TOKlbrace:
            e = parseObjectLiteral();
            break;

        case TOKfunction:
        {
            condition_block_depth.length++;
            // bool inside_function_block_save=inside_function_block;
            //  inside_function_block=true;
            // scope(exit) {
            //     inside_function_block=inside_function_block_save;
            // }
            auto start_func=p;
            e = parseFunctionLiteral();
            auto end_func=p;
            // e.source=start_func[0..cast(size_t)((end_func-start_func))];
            condition_block_depth.length--;
            break;
        }
        case TOKnew:
        { Expression newarg;
          Expression[] arguments;

          nextToken();
          newarg = parsePrimaryExp(1);
          arguments = parseArguments();
          e = new NewExp(loc, newarg, arguments);
          break;
        }
        case TOKillegalUnicode:
            error(errmsgtbl[ERR_EXPECTED_EXPRESSION_NOT_ILLEGAL], token.string);
            nextToken();
            return null;

            break;
        default:
            //	Lerror:
            error(errmsgtbl[ERR_EXPECTED_EXPRESSION], token.toText);
            nextToken();
            return null;
        }
        return parsePostExp(e, innew);
    }

    Expression[] parseArguments()
    {
        Expression[] arguments = null;

        if(token.value == TOK.TOKlparen)
        {
            nextToken();
            if(token.value != TOK.TOKrparen)
            {
                for(;; )
                {
                    Expression arg;

                    arg = parseAssignExp();
                    arguments ~= arg;
                    if(token.value == TOK.TOKrparen)
                        break;
                    if(!check(TOK.TOKcomma))
                        break;
                }
            }
            nextToken();
        }
        return arguments;
    }

    Expression parseArrayLiteral()
    {
        Expression e;
        Expression[] elements;
        Loc loc;

        // writef("parseArrayLiteral()\n");
        loc = currentline;
        check(TOK.TOKlbracket);
        if(token.value != TOK.TOKrbracket)
        {
            for(;; )
            {
                if(token.value == TOK.TOKcomma)
                    // Allow things like [1,2,,,3,]
                    // Like Explorer 4, and unlike Netscape, the
                    // trailing , indicates another null element.
					//Netscape was right - FIXED
                    elements ~= cast(Expression)null;
                else if(token.value == TOK.TOKrbracket)
                {
                    //elements ~= cast(Expression)null;
                    break;
                }
                else
                {
                    e = parseAssignExp();
                    elements ~= e;
                    if(token.value != TOK.TOKcomma)
                        break;
                }
                nextToken();
            }
        }
        check(TOK.TOKrbracket);
        e = new ArrayLiteral(loc, elements);
        return e;
    }

    Expression parseObjectLiteral()
    {
        Expression e;
        Field[] fields;
        Loc loc;
        uint[d_string] ids;
        //writef("parseObjectLiteral()\n");
        loc = currentline;
        check(TOK.TOKlbrace);
        if(token.value == TOK.TOKrbrace)
            nextToken();
        else
        {
            for(;; )
            {
                Field f;

                Field.type_t field_type;
                Identifier* ident;
                with(TOK) switch(token.value){
                case TOKidentifier:

                    ident = token.ident;
                    break;
                case TOKstring,TOKnumber,TOKreal:
                case TOKbreak, TOKcase, TOKdo:
                case TOKinstanceof, TOKtypeof, TOKelse:
                case TOKnew, TOKvar, TOKcatch:
                case TOKfinally, TOKreturn, TOKvoid:
                case TOKcontinue, TOKfor, TOKswitch:
                case TOKwhile, TOKdebugger, TOKfunction:
                case TOKthis, TOKwith, TOKdefault:
                case TOKif, TOKthrow, TOKdelete:
                case TOKnull, TOKtrue, TOKfalse:
                case TOKin, TOKtry, TOKclass:
                case TOKenum, TOKextends, TOKsuper:
                case TOKconst, TOKexport, TOKimport:
                    ident = Identifier(token.toText);
                    break;
                default:
                    error(errmsgtbl[ERR_EXPECTED_IDENTIFIER_NOT], token.toText);
                    break;
                }

                if (ident) {
                    auto istr=ident.toText;
                    switch (istr) {
                    case "set":
                        nextToken();
                        if (token.value != TOK.TOKcolon ) {
                            auto idtype=token.toText in ids;
                            if (idtype && ((*idtype) & ~Field.type_t.getter)) {
                                error(errmsgtbl[ERR_DUPLICATE_PROPERTY], token.toText);
                            }
                            field_type=Field.type_t.setter;
                            ident=Identifier(token.toText);
                            ids[token.toText]=(idtype)?(*idtype)|field_type:field_type;
                            nextToken();
                        }
                        break;
                    case "get":
                        nextToken();
                        if (token.value != TOK.TOKcolon ) {
                            auto idtype=token.toText in ids;
                            if (idtype && ((*idtype) & ~Field.type_t.setter)) {
                                error(errmsgtbl[ERR_DUPLICATE_PROPERTY], token.toText);
                            }
                            field_type=Field.type_t.getter;
                            ident=Identifier(token.toText);
                            ids[token.toText]=(idtype)?(*idtype)|field_type:field_type;
                            nextToken();
                        }
                        break;
                    default:
                        auto idtype=token.toText in ids;
                        if (idtype && (use_strict || ((*idtype) & ~Field.type_t.property)) ) {
                            error(errmsgtbl[ERR_DUPLICATE_PROPERTY], token.toText);
                        }
                        ids[token.toText]=(idtype)?(*idtype)|Field.type_t.property:Field.type_t.property;
                        nextToken();
                    }
                }
                if (field_type == Field.type_t.property) {
                    //   nextToken();
                    check(TOK.TOKcolon);
                    f = new Field(ident, parseAssignExp(), field_type);
                } else {
                    f = new Field(ident, parseSetGetter(ident, field_type == Field.type_t.setter), field_type);
                }
                fields ~= f;
                if(token.value != TOK.TOKcomma)
                    break;
                nextToken();
                if(token.value == TOK.TOKrbrace)//allow trailing comma
                    break;
            }
            check(TOK.TOKrbrace);
        }
        e = new ObjectLiteral(loc, fields);
        return e;
    }

    Expression parseFunctionLiteral()
    {
        FunctionDefinition f;
        Loc loc;
        loc = currentline;
        f = cast(FunctionDefinition)parseFunction(1);
        return new FunctionLiteral(loc, f);
    }

    Expression parsePostExp(Expression e, int innew)
    {
        Loc loc;
        for(;; )
        {
            loc = currentline;
            //loc = (Loc)token.ptr;

            with(TOK) switch(token.value)
            {
            case TOKdot:
                 version(Ecmascript5) {
                    // In Ecmascript 5 keyword is accepted as properties
                    // Checks that the next token is not taken
                    assert(token.next is null);
                    keyword_as_property=true;
                }
                nextToken();
                if(token.value == TOKidentifier)
                {
                    e = new DotExp(loc, e, token.ident);
                    version(Ecmascript5) {
                        keyword_as_property=false;
                    }
                }
                else
                {
                    error(errmsgtbl[ERR_EXPECTED_IDENTIFIER_2PARAM], ".", token.toText);
                    return e;
                }
                break;

            case TOKplusplus:
                if(token.sawLineTerminator && !(flags & inForHeader))
                    goto Linsert;
                e = new PostIncExp(loc, e);
                break;

            case TOKminusminus:
                if(token.sawLineTerminator && !(flags & inForHeader))
                {
                    Linsert:
                    // insert automatic semicolon
                    insertSemicolon(token.sawLineTerminator);
                    return e;
                }
                e = new PostDecExp(loc, e);
                break;

            case TOKlparen:
            {       // function call
                Expression[] arguments;

                if(innew)
                    return e;
                arguments = parseArguments();
                e = new CallExp(loc, e, arguments);
                continue;
            }

            case TOKlbracket:
            {       // array dereference
                Expression index;

                nextToken();
                index = parseExpression();
                check(TOKrbracket);
                e = new ArrayExp(loc, e, index);
                continue;
            }

            default:
                return e;
            }
            nextToken();
        }
        assert(0);
    }

    Expression parseUnaryExp()
    {
        Expression e;
        Loc loc;

        loc = currentline;
        with(TOK) switch(token.value)
        {
        case TOKplusplus:
            nextToken();
            e = parseUnaryExp();
            e = new PreExp(loc, IRcode.IRpreinc, e);
            break;

        case TOKminusminus:
            nextToken();
            e = parseUnaryExp();
            e = new PreExp(loc, IRcode.IRpredec, e);
            break;

        case TOKminus:
            nextToken();
            e = parseUnaryExp();
            e = new XUnaExp(loc, TOKneg, IRcode.IRneg, e);
            break;

        case TOKplus:
            nextToken();
            e = parseUnaryExp();
            e = new XUnaExp(loc, TOKpos, IRcode.IRpos, e);
            break;

        case TOKnot:
            nextToken();
            e = parseUnaryExp();
            e = new NotExp(loc, e);
            break;

        case TOKtilde:
            nextToken();
            e = parseUnaryExp();
            e = new XUnaExp(loc, TOKtilde, IRcode.IRcom, e);
            break;

        case TOKdelete:
            nextToken();
            e = parsePrimaryExp(0);
            e = new DeleteExp(loc, e);
            break;

        case TOKtypeof:
            nextToken();
            e = parseUnaryExp();
            e = new XUnaExp(loc, TOKtypeof, IRcode.IRtypeof, e);
            break;

        case TOKvoid:
            nextToken();
            e = parseUnaryExp();
            e = new XUnaExp(loc, TOKvoid, IRcode.IRundefined, e);
            break;

        default:
            e = parsePrimaryExp(0);
            break;
        }
        return e;
    }

    Expression parseMulExp()
    {
        Expression e;
        Expression e2;
        Loc loc;

        loc = currentline;
        e = parseUnaryExp();
        for(;; )
        {
            with(TOK) switch(token.value)
            {
            case TOKmultiply:
                nextToken();
                e2 = parseUnaryExp();
                e = new XBinExp(loc, TOKmultiply, IRcode.IRmul, e, e2);
                continue;

            case TOKregexp:
                // Rescan as if it was a "/"
                rescan();
            case TOKdivide:
                nextToken();
                e2 = parseUnaryExp();
                e = new XBinExp(loc, TOKdivide, IRcode.IRdiv, e, e2);
                continue;

            case TOKpercent:
                nextToken();
                e2 = parseUnaryExp();
                e = new XBinExp(loc, TOKpercent, IRcode.IRmod, e, e2);
                continue;

            default:
                break;
            }
            break;
        }
        return e;
    }

    Expression parseAddExp()
    {
        Expression e;
        Expression e2;
        Loc loc;

        loc = currentline;
        e = parseMulExp();
        for(;; )
        {
            with(TOK) switch(token.value)
            {
            case TOKplus:
                nextToken();
                e2 = parseMulExp();
                e = new AddExp(loc, e, e2);
                continue;

            case TOKminus:
                nextToken();
                e2 = parseMulExp();
                e = new XBinExp(loc, TOKminus, IRcode.IRsub, e, e2);
                continue;

            default:
                break;
            }
            break;
        }
        return e;
    }

    Expression parseShiftExp()
    {
        Expression e;
        Expression e2;
        Loc loc;

        loc = currentline;
        e = parseAddExp();
        for(;; )
        {
            IRcode ircode;
            TOK op = token.value;

            switch(op)
            {
            case TOK.TOKshiftleft:      ircode = IRcode.IRshl;         goto L1;
            case TOK.TOKshiftright:     ircode = IRcode.IRshr;         goto L1;
            case TOK.TOKushiftright:    ircode = IRcode.IRushr;        goto L1;

                L1: nextToken();
                e2 = parseAddExp();
                e = new XBinExp(loc, op, ircode, e, e2);
                continue;

            default:
                break;
            }
            break;
        }
        return e;
    }

    Expression parseRelExp()
    {
        Expression e;
        Expression e2;
        Loc loc;

        loc = currentline;
        e = parseShiftExp();
        for(;; )
        {
            IRcode ircode;
            TOK op = token.value;

            with(TOK) switch(op)
            {
            case TOKless:           ircode = IRcode.IRclt; goto L1;
            case TOKlessequal:      ircode = IRcode.IRcle; goto L1;
            case TOKgreater:        ircode = IRcode.IRcgt; goto L1;
            case TOKgreaterequal:   ircode = IRcode.IRcge; goto L1;

                L1:
                nextToken();
                e2 = parseShiftExp();
                e = new CmpExp(loc, op, ircode, e, e2);
                continue;

            case TOKinstanceof:
                nextToken();
                e2 = parseShiftExp();
                e = new XBinExp(loc, TOKinstanceof, IRcode.IRinstance, e, e2);
                continue;

            case TOKin:
                if(flags & noIn)
                    break;              // disallow
                nextToken();
                e2 = parseShiftExp();
                e = new InExp(loc, e, e2);
                continue;

            default:
                break;
            }
            break;
        }
        return e;
    }

    Expression parseEqualExp()
    {
        Expression e;
        Expression e2;
        Loc loc;

        loc = currentline;
        e = parseRelExp();
        for(;; )
        {
            IRcode ircode;
            TOK op = token.value;

            with(TOK) switch(op)
            {
            case TOKequal:       ircode = IRcode.IRceq;        goto L1;
            case TOKnotequal:    ircode = IRcode.IRcne;        goto L1;
            case TOKidentity:    ircode = IRcode.IRcid;        goto L1;
            case TOKnonidentity: ircode = IRcode.IRcnid;       goto L1;

                L1:
                nextToken();
                e2 = parseRelExp();
                e = new CmpExp(loc, op, ircode, e, e2);
                continue;

            default:
                break;
            }
            break;
        }
        return e;
    }

    Expression parseAndExp()
    {
        Expression e;
        Expression e2;
        Loc loc;

        loc = currentline;
        e = parseEqualExp();
        while(token.value == TOK.TOKand)
        {
            nextToken();
            e2 = parseEqualExp();
            e = new XBinExp(loc, TOK.TOKand, IRcode.IRand, e, e2);
        }
        return e;
    }

    Expression parseXorExp()
    {
        Expression e;
        Expression e2;
        Loc loc;

        loc = currentline;
        e = parseAndExp();
        while(token.value == TOK.TOKxor)
        {
            nextToken();
            e2 = parseAndExp();
            e = new XBinExp(loc, TOK.TOKxor, IRcode.IRxor, e, e2);
        }
        return e;
    }

    Expression parseOrExp()
    {
        Expression e;
        Expression e2;
        Loc loc;

        loc = currentline;
        e = parseXorExp();
        while(token.value == TOK.TOKor)
        {
            nextToken();
            e2 = parseXorExp();
            e = new XBinExp(loc, TOK.TOKor, IRcode.IRor, e, e2);
        }
        return e;
    }

    Expression parseAndAndExp()
    {
        Expression e;
        Expression e2;
        Loc loc;

        loc = currentline;
        e = parseOrExp();
        while(token.value == TOK.TOKandand)
        {
            nextToken();
            e2 = parseOrExp();
            e = new AndAndExp(loc, e, e2);
        }
        return e;
    }

    Expression parseOrOrExp()
    {
        Expression e;
        Expression e2;
        Loc loc;

        loc = currentline;
        e = parseAndAndExp();
        while(token.value == TOK.TOKoror)
        {
            nextToken();
            e2 = parseAndAndExp();
            e = new OrOrExp(loc, e, e2);
        }
        return e;
    }

    Expression parseCondExp()
    {
        Expression e;
        Expression e1;
        Expression e2;
        Loc loc;

        loc = currentline;
        e = parseOrOrExp();
        if(token.value == TOK.TOKquestion)
        {
            nextToken();
            e1 = parseAssignExp();

            check(TOK.TOKcolon);
            e2 = parseAssignExp();
            e = new CondExp(loc, e, e1, e2);
        }
        return e;
    }

    Expression parseAssignExp()
    {
        Expression e;
        Expression e2;
        Loc loc;

        loc = currentline;
        e = parseCondExp();
        for(;; )
        {
            IRcode ircode;
            TOK op = token.value;

            with(TOK) switch(op)
            {
            case TOKassign:
                nextToken();
                e2 = parseAssignExp();
                e = new AssignExp(loc, e, e2);
                continue;

            case TOKplusass:
                nextToken();
                e2 = parseAssignExp();
                e = new AddAssignExp(loc, e, e2);
                continue;

            case TOKminusass:       ircode = IRcode.IRsub;  goto L1;
            case TOKmultiplyass:    ircode = IRcode.IRmul;  goto L1;
            case TOKdivideass:      ircode = IRcode.IRdiv;  goto L1;
            case TOKpercentass:     ircode = IRcode.IRmod;  goto L1;
            case TOKandass:         ircode = IRcode.IRand;  goto L1;
            case TOKorass:          ircode = IRcode.IRor;   goto L1;
            case TOKxorass:         ircode = IRcode.IRxor;  goto L1;
            case TOKshiftleftass:   ircode = IRcode.IRshl;  goto L1;
            case TOKshiftrightass:  ircode = IRcode.IRshr;  goto L1;
            case TOKushiftrightass: ircode = IRcode.IRushr; goto L1;

                L1: nextToken();
                e2 = parseAssignExp();
                e = new BinAssignExp(loc, op, ircode, e, e2);
                continue;

            default:
                break;
            }
            break;
        }
        return e;
    }

    Expression parseExpression(uint flags = 0)
    {
        Expression e;
        Expression e2;
        Loc loc;
        uint flags_save;

        // writefln("Parser.parseExpression()");
        flags_save = this.flags;
        this.flags = flags;
        loc = currentline;
        e = parseAssignExp();
        while(token.value == TOK.TOKcomma)
        {
            nextToken();
            e2 = parseAssignExp();
            e = new CommaExp(loc, e, e2);
        }
        this.flags = flags_save;
        return e;
    }
}

/********************************* ***************************/
