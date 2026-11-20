module Main where

import StockCheck (reconcile)
import Control.Exception (IOException, evaluate, try)
import System.Directory (canonicalizePath, doesFileExist)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["--help"] -> putStr help
    [expected, counted] -> run expected counted Nothing
    [expected, counted, "--output", output] -> run expected counted (Just output)
    _ -> die help

help :: String
help = unlines ["StockCheck - offline inventory reconciliation in Haskell", "",
  "Usage: stockcheck EXPECTED.csv COUNTED.csv [--output REPORT.csv]", "",
  "Expected columns: sku,name,quantity,unit_price", "Counted columns:  sku,quantity", "",
  "Without --output, CSV goes to stdout; the summary goes to stderr.",
  "Output files must not already exist. Prices must share one currency.",
  "Missing counts are NOT zero. Only explicitly counted, known SKUs are valued."]

die :: String -> IO a
die message = hPutStrLn stderr message >> exitFailure

run :: FilePath -> FilePath -> Maybe FilePath -> IO ()
run expected counted output = do
  result <- try (work expected counted output) :: IO (Either IOException ())
  either (die . ("File error: " ++) . show) pure result

work :: FilePath -> FilePath -> Maybe FilePath -> IO ()
work expected counted output = do
  ep <- canonicalizePath expected
  cp <- canonicalizePath counted
  case output of
    Nothing -> pure ()
    Just path -> do
      op <- canonicalizePath path
      exists <- doesFileExist path
      if op == ep || op == cp || exists then die "Refusing to overwrite an input or existing report. Choose a new output path." else pure ()
  et <- strictRead expected
  ct <- strictRead counted
  case reconcile et ct of
    Left problem -> die ("Validation error: " ++ problem)
    Right (csv, summary) -> do
      maybe (putStr csv) (`writeFile` csv) output
      hPutStrLn stderr summary

strictRead :: FilePath -> IO String
strictRead path = do
  text <- readFile path
  _ <- evaluate (length text)
  pure text
