module StockCheck (parseCSV, renderCSV, reconcile) where

import Data.Char (isDigit, isSpace)
import Data.List (intercalate, sort)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Text.Read (readMaybe)

-- RFC-style CSV: quoted commas/newlines, doubled quotes, CRLF and UTF-8 BOM.
-- Strict after a closing quote: spaces outside quotes are not silently discarded.
parseCSV :: String -> Either String [[String]]
parseCSV input = scan Plain [] [] [] (dropBOM input)
  where
    dropBOM ('\xfeff':xs) = xs
    dropBOM xs = xs
    done field row rows = reverse (reverse (reverse field : row) : rows)
    scan mode field row rows xs = case (mode, xs) of
      (Quoted, []) -> Left "Unclosed quoted CSV field"
      (_, []) | null field && null row && mode == Plain -> Right (reverse rows)
      (_, []) -> Right (done field row rows)
      (Quoted, '"':'"':rest) -> scan Quoted ('"':field) row rows rest
      (Quoted, '"':rest) -> scan Closed field row rows rest
      (Quoted, x:rest) -> scan Quoted (x:field) row rows rest
      (Plain, '"':rest) | null field -> scan Quoted field row rows rest
      (Plain, '"':_) -> Left "Quote inside an unquoted CSV field"
      (_, ',':rest) -> scan Plain [] (reverse field:row) rows rest
      (_, '\r':'\n':rest) -> scan Plain [] [] (reverse (reverse field:row):rows) rest
      (_, '\n':rest) -> scan Plain [] [] (reverse (reverse field:row):rows) rest
      (_, '\r':_) -> Left "Bare carriage return outside quoted CSV field"
      (Closed, _) -> Left "Unexpected character after closing CSV quote"
      (Plain, x:rest) -> scan Plain (x:field) row rows rest

data Mode = Plain | Quoted | Closed deriving Eq

renderCSV :: [[String]] -> String
renderCSV = unlines . map (intercalate "," . map quote)
  where
    quote value | any (`elem` ",\"\r\n") value = '"' : concatMap escape value ++ "\""
                | otherwise = value
    escape '"' = "\"\""
    escape c = [c]

trim :: String -> String
trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace

natural :: String -> Either String Integer
natural s | not (null s) && all (\c -> isDigit c && c <= '9') s =
              maybe (Left "Invalid integer") Right (readMaybe s)
          | otherwise = Left "Expected a non-negative whole number"

money :: String -> Either String Integer
money s = case break (== '.') s of
  (whole, []) -> (*100) <$> natural whole
  (whole, '.':fraction) | length fraction `elem` [1,2] -> do
    a <- natural whole
    b <- natural fraction
    pure (100*a + if length fraction == 1 then 10*b else b)
  _ -> Left "Price must be non-negative with at most two decimal places"

formatMoney :: Integer -> String
formatMoney cents = sign ++ show whole ++ "." ++ (if part < 10 then "0" else "") ++ show part
  where
    sign = if cents < 0 then "-" else ""
    (whole, part) = abs cents `divMod` 100

data Item = Item { itemName :: String, itemQty :: Integer, itemPrice :: Integer }

-- Validate the whole file, including rows we might otherwise not use.
loadRows :: String -> [String] -> String -> Either String [M.Map String String]
loadRows label required text = do
  rows <- parseCSV text
  case rows of
    [] -> Left (label ++ ": empty CSV; a header is required")
    header:body -> do
      let keys = map trim header
      if length keys /= S.size (S.fromList keys) then Left (label ++ ": duplicate header") else pure ()
      if any null keys then Left (label ++ ": empty header") else pure ()
      if all (`elem` keys) required then pure () else Left (label ++ ": required columns: " ++ intercalate "," required)
      mapM (row keys) (zip [2 :: Int ..] body)
  where
    row keys (line, values)
      | length keys /= length values = Left (label ++ ": record " ++ show line ++ " has the wrong number of fields")
      | otherwise = Right (M.fromList (zip keys values))

getField :: String -> M.Map String String -> String
getField key = trim . M.findWithDefault "" key

unique :: [(String, a)] -> Either String (M.Map String a)
unique = go M.empty
  where
    go acc [] = Right acc
    go acc ((key,value):xs)
      | null key = Left "SKU cannot be empty"
      | M.member key acc = Left ("Duplicate SKU: " ++ key ++ ". Combine counts before importing.")
      | otherwise = go (M.insert key value acc) xs

withContext :: String -> Either String a -> Either String a
withContext label result = case result of
  Left problem -> Left (label ++ ": " ++ problem)
  Right value -> Right value

-- Returns (machine-readable report, human summary).
-- Missing counts are NOT interpreted as zero: valuation would be misleading.
reconcile :: String -> String -> Either String (String, String)
reconcile expectedText countedText = do
  expectedRows <- loadRows "Expected stock" ["sku","name","quantity","unit_price"] expectedText
  countedRows <- loadRows "Physical count" ["sku","quantity"] countedText
  expected <- mapM expectedItem expectedRows >>= unique
  counted <- mapM countedItem countedRows >>= unique
  let skus = sort (S.toList (M.keysSet expected `S.union` M.keysSet counted))
      results = map (compareItem expected counted) skus
      report = renderCSV (reportHeader : map fst results)
      values = [v | (_, Just v) <- results]
      total = sum values
      missing = length [() | sku <- skus, M.member sku expected, M.notMember sku counted]
      unknown = length [() | sku <- skus, M.notMember sku expected, M.member sku counted]
      matched = length [() | sku <- skus, Just i <- [M.lookup sku expected], Just q <- [M.lookup sku counted], itemQty i == q]
      summary = unlines ["StockCheck reconciliation", "SKUs: " ++ show (length skus) ++ "; matching: " ++ show matched,
                         "Missing physical counts: " ++ show missing ++ "; unknown SKUs: " ++ show unknown,
                         "Net variance value (compared, known-price SKUs only): " ++ formatMoney total,
                         "Currency follows your input prices. Missing counts and unknown SKUs are excluded from valuation."]
  pure (report, summary)
  where
    expectedItem r = withContext ("Expected SKU " ++ getField "sku" r) $ do
      q <- natural (getField "quantity" r)
      p <- money (getField "unit_price" r)
      pure (getField "sku" r, Item (M.findWithDefault "" "name" r) q p)
    countedItem r = withContext ("Counted SKU " ++ getField "sku" r) $ do
      q <- natural (getField "quantity" r)
      pure (getField "sku" r, q)

reportHeader :: [String]
reportHeader = ["sku","name","status","expected_qty","counted_qty","delta_qty","unit_price","variance_value"]

compareItem :: M.Map String Item -> M.Map String Integer -> String -> ([String], Maybe Integer)
compareItem expected counted sku = case (M.lookup sku expected, M.lookup sku counted) of
  (Just i, Just q) ->
    let delta = q - itemQty i
        value = delta * itemPrice i
        status | delta == 0 = "MATCH" | delta < 0 = "SHORTAGE" | otherwise = "OVERAGE"
    in ([sku,itemName i,status,show (itemQty i),show q,show delta,formatMoney (itemPrice i),formatMoney value], Just value)
  (Just i, Nothing) -> ([sku,itemName i,"NOT_COUNTED",show (itemQty i),"","",formatMoney (itemPrice i),""], Nothing)
  (Nothing, Just q) -> ([sku,"","UNKNOWN_SKU","",show q,"","",""], Nothing)
  (Nothing, Nothing) -> ([sku,"","INTERNAL_ERROR","","","","",""], Nothing)
