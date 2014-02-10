{-# LANGUAGE OverloadedStrings #-}
module Main where

import           Data.Aeson                     (toJSON, eitherDecode)
import           Data.Aeson.Encode.Pretty
import           Data.Text                      (Text)
import           Data.Map                       hiding (map)
import qualified Data.ByteString.Lazy           as B

import           Hunt.Common
import           Hunt.Index.Schema
import           Hunt.Interpreter.Interpreter
import           Hunt.Interpreter.Command
import           Hunt.Query.Ranking
import           Hunt.Query.Language.Grammar

main :: IO ()
main = do 
  -- init hunt interpreter.
  ix <- initEnv emptyIndexer defaultRankConfig contextTypes

  -- create context for publishing date.
  let cmd1 = InsertContext {
               -- context name
               icICon   = "publish_date",
               -- context schema: default schema for date context type
               -- Per default each context is created as default context.
               -- This means that every general query will per performed
               -- on this context. For the date context this might not
               -- be wanted, so we disable the default option.
               icSchema = (defSchema ctDate) { cxDefault = False }
             }
  putStrLn "1) Creating a new Context for the publishing date"
  putStrLn "JSON:"
  B.putStr . encodePretty $ cmd1
  -- we just discard the interpreter results in this demo
  -- in a real application the results should be handled to catch potential errors
  res <- runCmd ix cmd1
  putStrLn ""
  putStrLn "Press any key to continue..."
  _ <- getLine
  
  -- creating contexts for subject and the article context.
  -- commands can be batch executed by using the Sequnce operator. 
  let cmd2 = Sequence [
                -- context with default schema for text context type
                InsertContext "content" $ defSchema ctText,
                -- context with defaultSchema for text context type,
                -- but weight set to 2.0, to make this context twice
                -- as important as the other two
                InsertContext "subject" $ (defSchema ctText) { cxWeight = 2.0 }
              ]
  putStrLn "2) Executing multiple commands at once with Sequence. Here: Creating two contexts with one call."
  putStrLn "JSON:"
  B.putStr . encodePretty $ cmd2
  res <- runCmd ix cmd2
  putStrLn ""
  putStrLn "Press any key to continue..."
  _ <- getLine

  -- inserting a single document
  let cmd3 =  Insert ApiDocument {
                -- the documents unique identifier
                apiDocUri      = "id://6",
                -- the values that should be indexed
                apiDocIndexMap = fromList [ ("publish_date", "2014-02-15")
                                          , ("subject"     , "Another blog post")
                                          , ("content"     , "This is a short post ...")
                                          ],
                -- the values that should be stored for this document
                -- in the document table
                apiDocDescrMap = fromList [ ("date"   , "2014-02-15")
                                          , ("subject", "Another blog post")
                                          , ("content", "This is a short post ...")
                                          ]
              }

  putStrLn "3) Inserting a document"
  putStrLn "JSON:"
  B.putStr . encodePretty $ cmd3
  res <- runCmd ix cmd3
  putStrLn ""
  putStrLn "Press any key to continue..."
  _ <- getLine

  -- inserting a couple more documents from a file to be able to search
  -- with meaningful results. The format is the same so the JSON is not
  -- printed to the console here.
  fileContent <- B.readFile "apidocuments.js" 
  let cmd4 = case eitherDecode fileContent of
               (Right r) -> Sequence $ map Insert r
               _         -> error "error: file apidocuments.js not available or corrupt"
  res <- runCmd ix cmd4


  -- some search query examples
  -- first simple word search
  let query = Search (QWord QNoCase "sinis") 0 10
  putStrLn "4) Example query: simple search case in-sensitive for the word 'sinis'"
  putStrLn "JSON-Query:"
  B.putStr . encodePretty $ query
  res <- runCmd ix query
  putStrLn "Result:"
  B.putStr . encodePretty $ res
  putStrLn ""
  putStrLn "Press any key to continue..." 


  -- another example: searching for documents publised in january 2014
  let query2 = Search (QContext ["publish_date"] $ QRange "2014-01-01" "2014-01-31" ) 0 10
  putStrLn "4) Example query: simple search case in-sensitive for the word 'sinis'"
  putStrLn "JSON-Query:"
  B.putStr . encodePretty $ query2
  res <- runCmd ix query2
  putStrLn "Result:"
  B.putStr . encodePretty $ res
  putStrLn ""
  putStrLn "Press any key to exit" 
  return () 