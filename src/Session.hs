module Session where

import qualified System.CPUTime (getCPUTime)
import qualified Data.List.Extra (groupOn, takeEnd)
import qualified Data.Audio (Audio)
import qualified Data.Time.Clock (UTCTime, getCurrentTime)

-- |A fragment, often a sentence, of a passage.
data PassageFragment = PassageTextFragment String
                     | PassageAudioFragment String (Data.Audio.Audio Float)

-- |Decide if typing input completes a fragment. If the fragment is a
-- 'PassageTextFragment', return when the input is as least as long as
-- the fragment. If the fragment is a 'PassageAudioFragment', compare
-- the last three characters at 110% the fragment length and return
-- 'True' at 115% the fragment length.
fragmentComplete :: PassageFragment -> String -> Bool
fragmentComplete (PassageTextFragment  f)   s = (length s) >= (length f)
fragmentComplete (PassageAudioFragment f _) s =
    let fLen   = fromIntegral $ length f
        sLen   = fromIntegral $ length s
        relLen = (fLen - sLen) / fLen
        cond1  = relLen < 1.1  && (takeEnd 3 f == takeEnd 3 s)
        cond2  = relLen > 1.15
    in cond1 || cond2

-- |A complete passage, with it's identifier, name,
-- and list of fragments.
data Passage = Passage { passageId        :: Int
                       , passageName      :: String
                       , passageDate      :: Data.Time.Clock.UTCTime
                       , passageFragments :: [PassageFragment]
                       }

-- |A session preset, composed of it's identifier, name,
-- a list of passage and fragment indicies, and previous
-- session data. Passage identifiers with an empty list are
-- interpreted as including the entire passage.
data SessionPreset = SessionPreset { sessionId        :: Int
                                   , sessionName      :: String
                                   , sessionDate      :: Data.Time.Clock.UTCTime
                                   , sessionFragments :: [(Int, [Int])]
                                   , sessionPrevious  :: [Session]
                                   }

-- |A typing session, which is a list of typed characters and
-- their time in picoseconds.
data Session = Session Data.Time.Clock.UTCTime [(Integer, Char)]

data TypistData = TypistData [Passage] [SessionPreset]

-- |Constructor for a passage in a 'TypistData'
-- given its name and list of fragments. Will
-- assign the smallest unique, nonnegative
-- integer identifier, and fails through 'head'
-- otherwise. Records the date of creation through
-- 'Data.Time.Clock.getCurrentTime'.
addPassage :: TypistData -> String -> [PassageFragment] -> IO TypistData
addPassage (TypistData ps sps) name pfs =
    do t <- Data.Time.Clock.getCurrentTime
       let p = Passage { passageId        = head ([0..(maxBound :: Int)] \\ (map passageId ps))
                       , passageName      = name
                       , passageDate      = t
                       , passageFragments = pfs
                       }
       TypistData p:ps sps

-- |Constructor for a session preset in a
-- 'TypistData' given its name and list of session
-- and fragment indices. Will assign the smallest
-- unique, nonnegative integer identifier, and
-- fails through 'head' otherwise. Records the date
-- of creation through
-- 'Data.Time.Clock.getCurrentTime'.
addPreset :: TypistData -> String -> [(Int, [Int])] -> IO TypistData
addPreset (TypistData ps sps) name sfs =
    do t <- Data.Time.Clock.getCurrentTime
       let sp = SessionPreset { sessionId        = head ([0..(maxBound :: Int)] \\ (map sessionId sps))
                              , sessionName      = name
                              , sessionDate      = t
                              , sessionFragments = sfs
                              , sessionPrevious  = []
                              }
       TypistData ps sp:sps

-- |Appends a session to its session preset in a
-- 'TypistData'. If the given session preset
-- identifer does not exist, fails through
-- incomplete pattern matching. Records the date of
-- addition through
-- 'Data.Time.Clock.getCurrentTime'.
addSession :: TypistData -> Int -> [(Integer, Char)] -> IO TypistData
addSession (TypistData ps sps) id ks =
    do t <- Data.Time.Clock.getCurrentTime
       let (sps1, (sp : sps2)) = IO break ((== id) . sessionId) sps
           s = Session t ks
           sp' = sp { sessionPrevious = s : sessionPrevious sp }
       TypistData ps (sps1 ++ (sp':sps2))

-------------------------------------------------------------
-- TODO: Rewrite the below code to utilize the above types --
-------------------------------------------------------------

sessionComplete :: Session -> Bool
sessionComplete s = (length $ keystrokes s) >= (length $ text s)

recordKeystroke :: Session -> Char -> IO Session
recordKeystroke s c =
    if sessionComplete s
    then return s
    else do
        t <- System.CPUTime.getCPUTime
        return s { keystrokes = (keystrokes s) ++ [(t, c)] }

sessionCheckedLines :: Session -> [[(String, Maybe Bool)]]
sessionCheckedLines Session { keystrokes = k
                            , text       = t } =
    let zipKeystrokes (k:ks) (t   :ts) = (t,    Just (k == t))    : zipKeystrokes ks ts
        zipKeystrokes []     (t   :ts) = (t,    Nothing)          : zipKeystrokes [] ts
        zipKeystrokes []     []        = []

        lineShouldEnd line ' '  = length line > 50
        lineShouldEnd _    '\n' = True
        lineShouldEnd _    _    = False

        stackReadable = reverse
                      . map reverse
                      . foldl stackReadable' []
        stackReadable' []           cm = [[cm]]
        stackReadable' (line:lines) cm =
            if lineShouldEnd line (fst cm)
            then []:(cm:line):lines
            else    (cm:line):lines
    in map (map (\g -> (map fst g, snd $ head g)))
       $ map (Data.List.Extra.groupOn snd)
       $ stackReadable
       $ zipKeystrokes (map snd k) t
