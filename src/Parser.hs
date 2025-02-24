module Parser (
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
    pWhileLoopCondition,
    pUntilLoopCondition,
    pWhileLoop,
    pUntilLoop,
    pDoConditionalLoop,
    pForLoopRange,
    pForLoopBody,
    pForLoop,
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

import Helpers ((<:>))

import Text.Megaparsec (
    (<?>),
    choice,
    MonadParsec (hidden, try, eof),
    )

import Data.Functor((<&>), ($>), void)
import Control.Applicative((<|>), Alternative (many))
import Data.Text (unpack)

import Parser.Internal

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
pBoolean = pKeyword KeyWTrue $> True
        <|> pKeyword KeyWFalse $> False
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
    fCalls <- hidden $ many pExprList

    return $ foldl ExprFunctionCall base fCalls

pPrefixOpExpr :: Parser Expression
pPrefixOpExpr = do
    prefixes <- many pPrefixOp
    base <- pSuffixOpExpr

    return $ foldr ((ExprOperation . OpPrefix) .) base prefixes

pInfixlOpExpr :: Parser Expression -> Parser InfixOperator -> Parser Expression
pInfixlOpExpr pPrev pInfix = do
    base <- pPrev
    operations <- hidden $ many (liftA2 (,) pInfix pPrev)

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

pWhileLoopCondition :: Parser Expression
pWhileLoopCondition = do
    void (pKeyword KeyWWhile)
    void manyEol
    pGroupedExpression

pUntilLoopCondition :: Parser Expression
pUntilLoopCondition = do
    void (pKeyword KeyWUntil)
    void manyEol
    ExprOperation . OpPrefix . PreNot <$> pGroupedExpression

pWhileLoop :: Parser Expression
pWhileLoop = do
    condition <- pWhileLoopCondition
    void manyEol
    ExprWhileLoop condition <$> pExpression

pUntilLoop :: Parser Expression
pUntilLoop = do
    condition <- pUntilLoopCondition
    void manyEol
    ExprWhileLoop condition <$> pExpression

pDoConditionalLoop :: Parser Expression
pDoConditionalLoop = do
    void (pKeyword KeyWDo)
    void manyEol
    body <- pExpression
    void manyEol
    ExprDoWhileLoop body <$> choice
        [ pWhileLoopCondition
        , pUntilLoopCondition
        ]

pCorrectForLoopStep :: (VarIdentifier, Expression, Expression, Expression) -> (Expression, Expression, Expression, Expression)
pCorrectForLoopStep (varName, ExprAtomic (AtomIntLiteral start), ExprAtomic (AtomIntLiteral end), ExprAtomic (AtomIntLiteral step)) =
    case compare start end of
        LT -> (
                ExprAtomic (AtomIntLiteral start),
                ExprAtomic (AtomIntLiteral end),
                ExprAtomic (AtomIntLiteral step),
                ExprOperation $ OpInfix (InfixLt (ExprAtomic $ AtomIdentifier varName) (ExprAtomic (AtomIntLiteral end)))
            )
        _ -> (
                ExprAtomic (AtomIntLiteral start),
                ExprAtomic (AtomIntLiteral end),
                ExprAtomic (AtomIntLiteral (-step)),
                ExprOperation $ OpInfix (InfixGt (ExprAtomic $ AtomIdentifier varName) (ExprAtomic (AtomIntLiteral end)))
            )
pCorrectForLoopStep _ = error "Invalid range in for loop"

pForLoopRange :: VarIdentifier -> [Expression] -> (Expression, Expression, Expression, Expression)
pForLoopRange varName range = case range of
        [start, end] -> pCorrectForLoopStep (varName, start, end, ExprAtomic $ AtomIntLiteral 1)
        [start, end, step] -> pCorrectForLoopStep (varName, start, end, step)
        _ -> error "Invalid range in for loop"

pForLoopBody :: Expression -> Statement -> Expression
pForLoopBody body increment = ExprBlock $ BlockExpression $ case body of
    ExprBlock (BlockExpression stmts) -> stmts ++ [increment]
    _ -> [StExpression body, increment]

pForLoop :: Parser Expression
pForLoop = do
    void (pKeyword KeyWFor)
    void manyEol
    varDecl <- pVariableDecl
    void manyEol
    void (pKeyword KeyWIn)
    void manyEol
    range <- pExprList
    void manyEol
    body <- pExpression

    let VariableDeclaration (TypeIdentifier varType) varName = varDecl
        (start, _, step, condition) = pForLoopRange varName range
        assignment = StVariableDecl varDecl (Just start)
        increment = StAssignment varName (ExprOperation $ OpInfix (InfixAdd (ExprAtomic $ AtomIdentifier varName) step))
        body' = pForLoopBody body increment

        in case unpack varType of
            varType' | varType' `elem` ["i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64"] -> return $
                ExprForLoop $ BlockExpression [assignment, StExpression $ ExprWhileLoop condition body']
            _ -> fail ("Invalid type in for loop variable: " ++ unpack varType)

pExpression :: Parser Expression
pExpression = choice
    [ pOpExpr
    , pIfConditional
    , pUnlessConditional
    , pWhileLoop
    , pUntilLoop
    , pDoConditionalLoop
    , pForLoop
    ] <?> "expression"

pGroupedExpression :: Parser Expression
pGroupedExpression = pBetweenParenthesis pExpression

pExprList :: Parser [Expression]
pExprList = pBetweenParenthesis $ pCommaSep pExpression

pReturnStatement :: Parser Statement
pReturnStatement = StReturn <$> (pKeyword KeyWReturn *> pExpression)

pVariableDecl :: Parser VariableDeclaration
-- We might be able to remove the `try` here if type ids and var ids are different tokens
pVariableDecl = try (VariableDeclaration
    <$> pTypeIdentifier
    <*> pVarIdentifier
    <?> "variable declaration"
    )

pVariableDeclStatement :: Parser Statement
pVariableDeclStatement = do
    decl <- pVariableDecl
    value <- maybeParse (pControl OperAssign *> manyEol *> pExpression)
    return $ StVariableDecl decl value

pAssignStatement :: Parser Statement
pAssignStatement = try (StAssignment
    <$> pVarIdentifier
    <* pControl OperAssign
    <* manyEol
    <*> pExpression
    <?> "assignment statement"
    )

pStatement :: Parser Statement
pStatement = choice (map (<* pEndOfStatement)
    [ pReturnStatement
    , pVariableDeclStatement
    , pAssignStatement
    , pExpression <&> StExpression
    ]) <?> "statement"

pEndOfStatement :: Parser [Token]
pEndOfStatement = do
    x <- pControl Semicolon <|> eol
    xs <- manyEol
    return $ x:xs

pBlockExpression :: Parser BlockExpression
pBlockExpression = BlockExpression <$>
    pBetweenBrace (many pStatement)

pFunParamList :: Parser [VariableDeclaration]
pFunParamList = (pControl OpenParen *> manyEol *> pFunParamList') <|> pure []
    where
        -- Helper which recursively parses vdecls until a closing paren
        pFunParamList' :: Parser [VariableDeclaration]
        pFunParamList' = choice
            [ pControl CloseParen $> []
            , pVariableDecl <:> choice
                [ pControl CloseParen $> []
                , pControl Comma *> manyEol *> pFunParamList'
                ]
            ]


pReturnType :: Parser TypeIdentifier
pReturnType = pControl Colon *> manyEol *> pTypeIdentifier

pFunction :: Parser Function
pFunction = do
    void (pKeyword KeyWFun) <* manyEol
    name <- pIdentifier <* manyEol <?> "function name"
    paramList <- pFunParamList <* manyEol <?> "parameter list"
    retType <- maybeParse pReturnType <* manyEol <?> "return type"
    body <- pBlockExpression <* manyEol <?> "function body"

    return $ Function name paramList retType body
    <?> "function declaration"

pMainFunction :: Parser MainFunction
pMainFunction = do
    void (pKeyword KeyWMain) <* manyEol
    paramList <- pFunParamList <* manyEol
    body <- pBlockExpression <* manyEol

    return $ MainFunction paramList body
    <?> "main function"

pProgram :: Parser Program
pProgram = do
    preMain <- hidden $ many pFunction
    mainFunc <- pMainFunction
    postMain <- hidden $ many pFunction
    _ <- eof

    return $ Program mainFunc (preMain ++ postMain)
