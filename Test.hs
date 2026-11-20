module Main where

import StockCheck
import Control.Monad (forM_)
import Data.Either (isLeft)
import Data.List (isInfixOf)
import System.Exit (exitFailure)

expected :: String
expected = "sku,name,quantity,unit_price\nA,Fridge,5,100.50\nB,Fan,2,10.00\nC,TV,1,25\nD,Iron,4,1.01\n"
counted :: String
counted = "sku,quantity\nA,3\nB,2\nD,5\nX,7\n"

main :: IO ()
main = do
  let checks =
        [ ("quoted commas", parseCSV "a,\"b,c\"\n" == Right [["a","b,c"]])
        , ("escaped quotes", parseCSV "\"a\"\"b\"\n" == Right [["a\"b"]])
        , ("quoted newline", parseCSV "\"a\nb\",c\n" == Right [["a\nb","c"]])
        , ("CRLF", parseCSV "a,b\r\nc,d\r\n" == Right [["a","b"],["c","d"]])
        , ("BOM", parseCSV "\xfeff\&sku,quantity\n" == Right [["sku","quantity"]])
        , ("trailing field", parseCSV "a," == Right [["a",""]])
        , ("empty quoted field", parseCSV "\"\"" == Right [[""]])
        , ("empty input", parseCSV "" == Right [])
        , ("unclosed quote rejected", isLeft (parseCSV "\"a"))
        , ("unquoted quote rejected", isLeft (parseCSV "a\"b"))
        , ("trailing quote garbage rejected", isLeft (parseCSV "\"a\"x"))
        , ("bare CR rejected", isLeft (parseCSV "a\rb"))
        , ("reconciliation statuses", case reconcile expected counted of
              Right (csv, summary) -> all (`isInfixOf` csv) ["SHORTAGE","MATCH","OVERAGE","NOT_COUNTED","UNKNOWN_SKU","-201.00","1.01"] && "-199.99" `isInfixOf` summary
              _ -> False)
        , ("missing count not valued", case reconcile expected "sku,quantity\n" of
              Right (csv,summary) -> "NOT_COUNTED" `isInfixOf` csv && "only): 0.00" `isInfixOf` summary
              _ -> False)
        , ("duplicate SKU rejected", isLeft (reconcile expected "sku,quantity\nA,1\nA,2\n"))
        , ("negative count rejected", isLeft (reconcile expected "sku,quantity\nA,-1\n"))
        , ("fractional count rejected", isLeft (reconcile expected "sku,quantity\nA,1.2\n"))
        , ("blank SKU rejected", isLeft (reconcile expected "sku,quantity\n,1\n"))
        , ("missing header rejected", isLeft (reconcile expected "item,quantity\nA,1\n"))
        , ("duplicate header rejected", isLeft (reconcile expected "sku,quantity,quantity\nA,1,2\n"))
        , ("row width rejected", isLeft (reconcile expected "sku,quantity\nA,1,extra\n"))
        , ("blank record rejected", isLeft (reconcile expected "sku,quantity\n\n"))
        , ("sub-cent price rejected", isLeft (reconcile "sku,name,quantity,unit_price\nA,X,1,1.001\n" counted))
        , ("one-digit cents", case reconcile "sku,name,quantity,unit_price\nA,X,1,1.2\n" "sku,quantity\nA,2\n" of
              Right (csv,_) -> "1.20,1.20" `isInfixOf` csv
              _ -> False)
        , ("large integer exactness", case reconcile "sku,name,quantity,unit_price\nA,X,9007199254740993,0.01\n" "sku,quantity\nA,9007199254740994\n" of
              Right (csv,_) -> ",1,0.01,0.01" `isInfixOf` csv
              _ -> False)
        , ("Unicode name preserved", case reconcile "sku,name,quantity,unit_price\nA,മലയാളം,1,1\n" "sku,quantity\nA,1\n" of
              Right (csv,_) -> "മലയാളം" `isInfixOf` csv
              _ -> False)
        , ("extra columns allowed", case reconcile expected "quantity,sku,note\n3,A,ok\n" of Right _ -> True; _ -> False)
        , ("CSV round trip", all (\rows -> parseCSV (renderCSV rows) == Right rows)
              [[["a","b"]],[["","comma,quote\"","line\nfeed"]],[["മലയാളം","0"]]])
        ]
  forM_ checks $ \(name, ok) -> putStrLn ((if ok then "PASS " else "FAIL ") ++ name)
  if and (map snd checks) then putStrLn (show (length checks) ++ " tests passed") else exitFailure
