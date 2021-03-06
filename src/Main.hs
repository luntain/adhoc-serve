{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import qualified Data.ByteString.Char8 as B
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import Data.List (break)
import Options.Applicative as Opt
import Snap.Core
import Snap.Http.Server
import Snap.Util.FileServe
import Snap.Util.GZip
import System.Environment (getArgs)
import System.Random
import Data.String (IsString(fromString))
import Network.HostName
import Data.Text (Text)
import Control.Monad (forM)
import Data.Foldable (msum)

main :: IO ()
main = do
  Run { port, dirsToServe } <- execParser cliParser
  dirsToServe' :: [(FilePath, B.ByteString)] <- forM dirsToServe $ \(DirToServe path mprefix) ->
    (path,) <$> maybe randomGuid pure mprefix

  let conf = config port
  print conf
  hostName <- getHostName

  if null dirsToServe' then putStrLn "No dirs given, see --help"
    else do
      putStrLn $ "Serving following dirs:"
      forM dirsToServe' $ \(diskPath, prefix) -> do
        putStrLn $ " * " ++ diskPath ++ " at " ++ "http://" ++ hostName ++ ":" ++ show port ++ "/" ++ B.unpack prefix ++ "/"

      httpServe conf
        . withCompression' (Set.insert "text/csv" compressibleMimeTypes)
        . msum
        . flip map dirsToServe'
        $ \(diskPath, prefix) -> dir prefix $ serveDirectoryWith fancyDirectoryConfig diskPath

  where
    config port =
      setErrorLog ConfigNoLog
        . setAccessLog ConfigNoLog
        . setPort port
        $ defaultConfig

    randomGuid :: IO B.ByteString
    randomGuid = UUID.toASCIIBytes <$> randomIO


cliParser :: ParserInfo Cmd
cliParser =
  info
    (options <**> helper)
    ( fullDesc
        <> header "Ad-hoc HTTP file server" -- I have no idea where or when it displays
        <> progDesc "Serve a directory under a randomly generated GUID or a specified path"
    )

options :: Parser Cmd
options =
  Run
    <$> option auto (long "port" <> short 'p' <> value 7878 <> showDefault <> metavar "INT")
    <*> many dirToServe

dirToServe :: Parser DirToServe
dirToServe =
  Opt.argument (Opt.maybeReader parse) (
            metavar "DIR[:URL_PREFIX]"
          <> help "The path to directory on disk to serve over HTTP and, optionally, the URL prefix\
                  \ under which the tree of files will be served (a random GUID by default)")
  where
    parse x =
      case break (==':') x of
        (dir, []) -> Just (DirToServe dir Nothing)
        (dir, ':' : prefix) -> Just $ DirToServe  dir (Just (fromString prefix))
        _ -> error "Impossible!"


data Cmd = Run { port :: Int, dirsToServe :: [DirToServe]}
data DirToServe = DirToServe { path :: FilePath, pathPrefix :: Maybe B.ByteString}
