module Main where

import Network.Socket
import System.IO
import Control.Exception
import Control.Concurrent
import Control.Concurrent.Chan
import Control.Monad (liftM, when)
import Control.Monad.Fix (fix)

main :: IO ()
main = do
  sock <- socket AF_INET Stream 0 -- create socket
  setSocketOption sock ReuseAddr 1 -- make socket immediately reusable
  bind sock (SockAddrInet 4242 iNADDR_ANY) -- listen on TCP port 4242
  listen sock 2 -- set a maximum of two queued connections
  chan <- newChan
  forkIO $ fix $ \loop -> do
    (_, msg) <- readChan chan
    loop
  mainLoop sock chan 0

type Msg = (Int, String)

mainLoop :: Socket -> Chan Msg -> Int -> IO ()
mainLoop sock chan msgNum = do
  conn <- accept sock -- accept a connection and handle it
  forkIO (runConn conn chan msgNum) --run our server's logic
  mainLoop sock chan $! msgNum + 1 -- repeat

runConn :: (Socket, SockAddr) -> Chan Msg -> Int -> IO()
runConn (sock, _) chan msgNum = do
  let broadcast msg = writeChan chan (msgNum, msg)
  hdl <- socketToHandle sock ReadWriteMode
  hSetBuffering hdl NoBuffering

  name <- liftM init (hGetLine hdl) -- get name of client

  commLine <- dupChan chan

  reader <- forkIO $ fix $ \loop -> do
    (nextNum, line) <- readChan commLine
    when (msgNum /= nextNum) $ hPutStrLn hdl line
    loop

  handle (\(SomeException _) -> return()) $ fix $ \loop -> do
    line <- liftM init (hGetLine hdl)
    case line of -- pattern match the line
      -- If an exception is caught, send a message and break the loop
      "quit" -> hPutStrLn hdl "Bye"
      -- else, continue looping
      _      -> broadcast (name ++ ": " ++ line) >> loop

  killThread reader
  broadcast (name ++ ": exited")
  hClose hdl
  hClose hdl
