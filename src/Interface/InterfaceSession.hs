module Interface.InterfaceSession where

import Passage
import Interface

import Themes

import qualified Brick as B
import qualified Graphics.Vty as V

import qualified Data.List.Extra
import qualified Data.Time.Clock.System
import qualified Control.Monad.IO.Class

data InterfaceSession = InterfaceSession { passages   :: [Passage]
                                         , begin      :: Maybe Data.Time.Clock.System.SystemTime
                                         , keystrokes :: [Keystroke]
                                         }

instance Interface InterfaceSession where
    input interface (B.VtyEvent (V.EvKey V.KEsc []))      = B.halt interface
    input interface (B.VtyEvent (V.EvKey (V.KChar c) [])) = Control.Monad.IO.Class.liftIO (record interface c)    >>= B.continue
    input interface (B.VtyEvent (V.EvKey V.KEnter    [])) = Control.Monad.IO.Class.liftIO (record interface '\n') >>= B.continue
    input interface _                                     = B.continue interface
    draw  interface =
        let checkedLines = map groupByScore
                         $ groupByLines
                         $ Passage.render (head interface.passages) interface.keystrokes
            normalLines = B.vBox
                        $ map B.hBox
                        $ map (map (\(s, m) -> themeRendered themeNormal (filter (/= '\n') s) m))
                        $ checkedLines
            specialLines = B.vBox
                         $ map (\(s, m) -> case last s of
                                           '\n' -> themeRendered themeSpecial "\\n" m
                                           _    -> themeRendered themeSpecial "<-"  m)
                         $ map last
                         $ checkedLines
        in normalLines B.<+> specialLines

record :: InterfaceSession -> Char -> IO InterfaceSession
record td c =
    do t <- Data.Time.Clock.System.getSystemTime
       case td.begin of
           Just begin' -> return td{keystrokes ++ [Keystroke ((asCentiseconds t) - (asCentiseconds begin')) c]}
           Nothing     -> return td{keystrokes ++ [Keystroke 0 c],
                                    begin = Just t}

themeRendered :: B.AttrName -> String -> Maybe Bool -> B.Widget ()
themeRendered t s Nothing = B.showCursor () (B.Location (0, 0))
                          $ B.withAttr t
                          $ B.str s
themeRendered t s (Just True)  = B.withAttr (t <> themeMatch) $ B.str s
themeRendered t s (Just False) = B.withAttr (t <> themeMiss)  $ B.str s

asCentiseconds :: Data.Time.Clock.System.SystemTime -> Int
asCentiseconds x =
    let seconds'     = (fromIntegral $ Data.Time.Clock.System.systemSeconds x)     * 100           :: Int
        nanoseconds' = (fromIntegral $ Data.Time.Clock.System.systemNanoseconds x) `quot` 10000000 :: Int
    in seconds' + nanoseconds'

groupByLines :: [(Char, Maybe Bool)] -> [[(Char, Maybe Bool)]]
groupByLines x =
    let lineShouldEnd l  ' '  = length l > 50
        lineShouldEnd _  '\n' = True
        lineShouldEnd _  _    = False
        stackReadable [] c     = [[c]]
        stackReadable (l:ls) c =
            if lineShouldEnd l (fst c)
            then []:(c:l):ls
            else    (c:l):ls
    in map reverse
       $ reverse
       $ foldl stackReadable [] x

groupByScore :: [(Char, Maybe Bool)] -> [(String, Maybe Bool)]
groupByScore x =
    let collapseSameScore [] = ([],        Nothing)
        collapseSameScore l  = (map fst l, snd $ head l)
    in map collapseSameScore
       $ Data.List.Extra.groupOn snd x
