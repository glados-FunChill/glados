{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}

module Parser where

import Text.Megaparsec
    ( Parsec
    , MonadParsec (lookAhead, hidden, eof, takeWhile1P)
    , choice
    , skipSome
    )
import Data.Void (Void)
import Lib
    ( Primitive (Boolean, Constant, SymbolReference)
    , Symbol (Symbol)
    )
import Text.Megaparsec.Char (space1, char)
import Data.Functor (($>), void)
import Control.Applicative ((<|>))
import qualified Text.Megaparsec.Char.Lexer as L
import Text.Megaparsec.Char.Lexer (signed)
import Data.Text (Text, unpack, uncons, all, splitAt)
import Data.Char
    ( isSpace
    , generalCategory
    , GeneralCategory
        ( UppercaseLetter
        , LowercaseLetter
        , TitlecaseLetter
        , ModifierLetter
        , OtherLetter
        , NonSpacingMark
        , LetterNumber
        , OtherNumber
        , DashPunctuation
        , OtherPunctuation
        , CurrencySymbol
        , MathSymbol
        , ModifierSymbol
        , OtherSymbol
        , PrivateUse
        , DecimalNumber
        , SpacingCombiningMark
        , EnclosingMark
        )
    )

type Parser = Parsec Void Text

-- Helper function to combine predicates
(.||) :: (a -> Bool) -> (a -> Bool) -> a -> Bool
(.||) f1 f2 x = f1 x || f2 x

chezSchemeNonSpaceDelimiter :: String
chezSchemeNonSpaceDelimiter = "()[]#\";"

-- Checks if a character is a valid initial for a symbol name,
-- as defined in https://scheme.com/tspl4/grammar.html#APPENDIXFORMALSYNTAX
isChezSchemeSymbolInitial :: Char -> Bool
isChezSchemeSymbolInitial c
    = c `elem` basicLetters
    || (c > '\x7f' && generalCategory c `elem` [
        UppercaseLetter,
        LowercaseLetter,
        TitlecaseLetter,
        ModifierLetter,
        OtherLetter,
        NonSpacingMark,
        LetterNumber,
        OtherNumber,
        DashPunctuation,
        OtherPunctuation,
        CurrencySymbol,
        MathSymbol,
        ModifierSymbol,
        OtherSymbol,
        PrivateUse
    ])
    where basicLetters = ['a'..'z'] ++ ['A'..'Z'] ++ "!$%&*/:<=>?~_^"

-- Checks if a character is a valid non-initial for a symbol name,
-- as defined in https://scheme.com/tspl4/grammar.html#APPENDIXFORMALSYNTAX
isChezSchemeSymbolSubsequent :: Char -> Bool
isChezSchemeSymbolSubsequent c
    = isChezSchemeSymbolInitial c
    || c `elem` ['0'..'9'] ++ ".+-@"
    || generalCategory c `elem` [
        DecimalNumber,
        SpacingCombiningMark,
        EnclosingMark
    ]

isChezSchemeDelimiter :: Char -> Bool
isChezSchemeDelimiter = isSpace .|| (`elem` chezSchemeNonSpaceDelimiter)

-- Patched version of Text.MegaParsec.Char.Lexer.space
-- to only succeed if some space is encountered, or at eof
someSpace :: MonadParsec e s m => m a -> m a -> m a -> m ()
someSpace sp line block = skipSome (choice
    [hidden sp, hidden line, hidden block]
    ) <|> eof

-- Parse any amount of whitespace or chez-scheme comments
pWhiteSpace :: Parser ()
pWhiteSpace = someSpace
    space1
    (L.skipLineComment ";")
    (L.skipBlockComment "#|" "|#")

-- Check if the next character is part of
-- the string passed in argument, but do not consume it
pDelimiterCharacter :: String -> Parser ()
pDelimiterCharacter = choice . map (void . lookAhead . char)

-- Parse delimiter between two identifiers:
-- - either some whitespace/comment (which will be consumed)
-- - or the next character is a delimiter which will not be consumed
pDelimiter :: Parser ()
pDelimiter = pWhiteSpace <|> pDelimiterCharacter chezSchemeNonSpaceDelimiter

-- Parse a chez-scheme lexeme: apply the parser
-- passed as parameter and then check make sure we
-- reached a delimiter, and consume it appropriately
pLexeme :: Parser a -> Parser a
pLexeme = L.lexeme pDelimiter

-- Similar to pLexeme but intended for parsing know strings
pSymbol :: Text -> Parser Text
pSymbol = L.symbol pDelimiter

-- pSymbol, case insensitive
pSymbol' :: Text -> Parser Text
pSymbol' = L.symbol' pDelimiter

parseUntilDelimiter :: Parser Text
parseUntilDelimiter = takeWhile1P
    (Just "any non-delimiter character")
    (not . isChezSchemeDelimiter)

parseSymName :: Parser Text
parseSymName = do
    tok <- parseUntilDelimiter
    if checkSymName tok then
        return tok
    else
        fail "Symbol contains invalid character(s)"

    where
        -- Symbol names can contain almost any characters but
        -- have very weird constraints.
        -- See https://scheme.com/tspl4/grammar.html#Strings for details
        checkSymName :: Text -> Bool
        checkSymName "+" = True
        checkSymName "-" = True
        checkSymName "..." = True
        checkSymName (Data.Text.splitAt 2 -> ("->", subsequents))
            = Data.Text.all isChezSchemeSymbolSubsequent subsequents
        checkSymName (uncons -> (Just (initial, subsequents)))
            = isChezSchemeSymbolInitial initial
            && Data.Text.all isChezSchemeSymbolSubsequent subsequents
        checkSymName _ = False

-- Parser for chez-scheme boolean literals #f and #t
booleanParser :: Parser Primitive
booleanParser = (pSymbol' "#t" $> Boolean True) <|> (pSymbol' "#f" $> Boolean False)

-- Parser for chez-scheme string literals
stringParser :: Parser Primitive
stringParser = undefined

-- Parser for chez-scheme integer literals
integerParser :: Parser Primitive
integerParser = Constant <$> pLexeme (signed (return ()) L.decimal)

-- Parser for symbol references
symbolRefParser :: Parser Primitive
symbolRefParser = pLexeme (SymbolReference . Symbol . unpack <$> parseSymName)

-- Parser for lambda declaration
lambdaParser :: Parser Primitive
lambdaParser = undefined
