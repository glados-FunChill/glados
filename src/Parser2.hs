module Parser2 (
    pIntLiteral,
    pVarIdentifier,
    pTypeIdentifier,
    pBoolean,
    pAtom,
    pPrimaryExpression,
    pPrefixOp,
    pMultiplyOp,
    pAdditionOp,
    pComparisonOp,
    pEqualityOp,
    pLogicalAndOp,
    pLogicalOrOp,
    pSuffixOpExpr,
    pPrefixOpExpr,
    pInfixlOpExpr,
    pMultiplyOpExpr,
    pAdditionOpExpr,
    pComparisonOpExpr,
    pEqualityOpExpr,
    pLogicalAndExpr,
    pLogicalOrExpr,
    pOpExpr,
    pConditionalBody,
    pIfConditional,
    pUnlessConditional,
    pExpression,
    pGroupedExpression,
    pExprList,
    pReturnStatement,
    pVariableDecl,
    pVariableDeclStatement,
    pStatement,
    pEndOfStatement,
    pBlockExpression,
    pFunParamList,
    pReturnType,
    pFunction,
    pMainFunction,
    pProgram,
) where

import Text.Megaparsec (
    (<?>),
    choice,
    )

import Data.Functor((<&>), ($>), void)
import Control.Applicative((<|>), Alternative (many))

import Parser.Internal2

import Lexer.Tokens (
    Token(..),
    Keyword (..),
    ControlSequence (..),
    )
import Parser.AST (
    VarIdentifier (VarIdentifier),
    TypeIdentifier (TypeIdentifier),
    AtomicExpression (..),
    Expression (..),
    Statement (..),
    VariableDeclaration (VariableDeclaration),
    BlockExpression (BlockExpression),
    PrefixOperation (..),
    Operation (OpPrefix, OpInfix),
    InfixOperation (..),
    PrefixOperator,
    InfixOperator,
    Function (Function),
    MainFunction (MainFunction),
    Program (Program),
    )

pVarIdentifier :: Parser VarIdentifier
pVarIdentifier = pIdentifier <&> VarIdentifier <?> "variable identifier"

pTypeIdentifier :: Parser TypeIdentifier
pTypeIdentifier = pIdentifier <&> TypeIdentifier <?> "type identifier"

pBoolean :: Parser Bool
pBoolean = (pKeyword KeyWTrue $> True
        <|> pKeyword KeyWFalse $> False)
        <?> "boolean literal"

pAtom :: Parser AtomicExpression
pAtom = choice
    [ pIntLiteral       <&> AtomIntLiteral
    , pVarIdentifier    <&> AtomIdentifier
    , pBoolean          <&> AtomBooleanLiteral
    ]

pPrimaryExpression :: Parser Expression
pPrimaryExpression = choice
    [ pAtom             <&> ExprAtomic
    , pBlockExpression  <&> ExprBlock
    , pGroupedExpression
    ]

pPrefixOp :: Parser PrefixOperator
pPrefixOp = choice
    [ pControl OperSub $> PreNeg
    , pControl OperNot $> PreNot
    , pControl OperAdd $> PrePlus
    ]

pMultiplyOp :: Parser InfixOperator
pMultiplyOp = choice
    [ pControl OperMul $> InfixMul
    , pControl OperDiv $> InfixDiv
    , pControl OperMod $> InfixMod
    ]

pAdditionOp :: Parser InfixOperator
pAdditionOp = choice
    [ pControl OperAdd $> InfixAdd
    , pControl OperSub $> InfixSub
    ]

pComparisonOp :: Parser InfixOperator
pComparisonOp = choice
    [ pControl OperGt $> InfixGt
    , pControl OperLt $> InfixLt
    , pControl OperGe $> InfixGe
    , pControl OperLe $> InfixLe
    ]

pEqualityOp :: Parser InfixOperator
pEqualityOp = choice
    [ pControl OperEquals $> InfixEq
    , pControl OperDiffer $> InfixNeq
    ]

pLogicalAndOp :: Parser InfixOperator
pLogicalAndOp = pControl OperAnd $> InfixAnd

pLogicalOrOp :: Parser InfixOperator
pLogicalOrOp = pControl OperOr $> InfixOr


pSuffixOpExpr :: Parser Expression
pSuffixOpExpr = do
    base <- pPrimaryExpression
    fCalls <- many pExprList

    return $ foldl ExprFunctionCall base fCalls

pPrefixOpExpr :: Parser Expression
pPrefixOpExpr = do
    prefixes <- many pPrefixOp
    base <- pSuffixOpExpr

    return $ foldr ((ExprOperation . OpPrefix) .) base prefixes

pInfixlOpExpr :: Parser Expression -> Parser InfixOperator -> Parser Expression
pInfixlOpExpr pPrev pInfix = do
    base <- pPrev
    operations <- many (liftA2 (,) pInfix pPrev)

    return $ foldl
        (\acc (oper, expr) -> ExprOperation $ OpInfix $ oper acc expr)
        base
        operations

pMultiplyOpExpr :: Parser Expression
pMultiplyOpExpr = pInfixlOpExpr pPrefixOpExpr pMultiplyOp

pAdditionOpExpr :: Parser Expression
pAdditionOpExpr = pInfixlOpExpr pMultiplyOpExpr pAdditionOp

pComparisonOpExpr :: Parser Expression
pComparisonOpExpr = pInfixlOpExpr pAdditionOpExpr pComparisonOp

pEqualityOpExpr :: Parser Expression
pEqualityOpExpr = pInfixlOpExpr pComparisonOpExpr pEqualityOp

pLogicalAndExpr :: Parser Expression
pLogicalAndExpr = pInfixlOpExpr pEqualityOpExpr pLogicalAndOp

pLogicalOrExpr :: Parser Expression
pLogicalOrExpr = pInfixlOpExpr pLogicalAndExpr pLogicalOrOp

pOpExpr :: Parser Expression
pOpExpr = pLogicalOrExpr

pConditionalBody :: Parser (Expression, Expression, Maybe Expression)
pConditionalBody = do
    condition <- pGroupedExpression
    void manyEol
    firstArm <- pExpression
    secondArm <- tryParse $ do
        void manyEol
        void (pKeyword KeyWElse)
        void manyEol
        pExpression

    return (condition, firstArm, secondArm)

pIfConditional :: Parser Expression
pIfConditional = do
    void (pKeyword KeyWIf)
    void manyEol
    (condition, firstArm, secondArm) <- pConditionalBody

    return $ ExprIfConditional condition firstArm secondArm

pUnlessConditional :: Parser Expression
pUnlessConditional = do
    void (pKeyword KeyWUnless)
    void manyEol
    (condition, firstArm, secondArm) <- pConditionalBody

    let condition' = ExprOperation $ OpPrefix $ PreNot condition
    return $ ExprIfConditional condition' firstArm secondArm

pExpression :: Parser Expression
pExpression = choice
    [ pOpExpr
    , pIfConditional
    , pUnlessConditional
    ] <?> "expression"

pGroupedExpression :: Parser Expression
pGroupedExpression = pBetweenParenthesis pExpression

pExprList :: Parser [Expression]
pExprList = pBetweenParenthesis $ pCommaSep pExpression

pReturnStatement :: Parser Statement
pReturnStatement = StReturn <$> (pKeyword KeyWReturn *> pExpression)

pVariableDecl :: Parser VariableDeclaration
pVariableDecl = VariableDeclaration
    <$> pTypeIdentifier
    <*> pVarIdentifier

pVariableDeclStatement :: Parser Statement
pVariableDeclStatement = do
    decl <- pVariableDecl
    value <- tryParse (pControl OperEquals *> pExpression)
    return $ StVariableDecl decl value

pStatement :: Parser Statement
pStatement = choice
    [ pReturnStatement
    , pVariableDeclStatement
    , pExpression <&> StExpression
    ]

pEndOfStatement :: Parser [Token]
pEndOfStatement = do
    x <- pControl Semicolon <|> eol
    xs <- many eol
    return $ x:xs

pBlockExpression :: Parser BlockExpression
pBlockExpression = BlockExpression <$>
    pBetweenBrace (many (pStatement <* pEndOfStatement))

pFunParamList :: Parser [VariableDeclaration]
pFunParamList = pBetweenParenthesis $ pCommaSep pVariableDecl

pReturnType :: Parser TypeIdentifier
pReturnType = pControl Colon *> manyEol *> pTypeIdentifier

pFunction :: Parser Function
pFunction = do
    void (pKeyword KeyWFun) <* manyEol
    name <- pIdentifier <* manyEol
    paramList <- pFunParamList <* manyEol
    retType <- tryParse pReturnType <* manyEol
    body <- pBlockExpression <* manyEol

    return $ Function name paramList retType body

pMainFunction :: Parser MainFunction
pMainFunction = do
    void (pKeyword KeyWMain) <* manyEol
    paramList <- pFunParamList <* manyEol
    body <- pBlockExpression <* manyEol

    return $ MainFunction paramList body

pProgram :: Parser Program
pProgram = do
    preMain <- many pFunction
    mainFunc <- pMainFunction
    postMain <- many pFunction

    return $ Program mainFunc (preMain ++ postMain)
