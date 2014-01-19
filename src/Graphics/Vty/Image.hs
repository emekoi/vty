-- Copyright 2009-2010 Corey O'Connor
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE DisambiguateRecordFields #-}
module Graphics.Vty.Image ( DisplayText
                          , Image
                          , image_width
                          , image_height
                          , horiz_join
                          , (<|>)
                          , vert_join
                          , (<->)
                          , horiz_cat
                          , vert_cat
                          , background_fill
                          , text
                          , text'
                          , char
                          , string
                          , iso_10646_string
                          , utf8_string
                          , utf8_bytestring
                          , utf8_bytestring'
                          , char_fill
                          , empty_image
                          , safe_wcwidth
                          , safe_wcswidth
                          , wcwidth
                          , wcswidth
                          , crop
                          , crop_right
                          , crop_left
                          , crop_bottom
                          , crop_top
                          , pad
                          , resize
                          , resize_width
                          , resize_height
                          , translate
                          , translate_x
                          , translate_y
                          -- | The possible display attributes used in constructing an `Image`.
                          , module Graphics.Vty.Attributes
                          )
    where

import Graphics.Vty.Attributes
import Graphics.Vty.Image.Internal
import Graphics.Text.Width

import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TL
import Data.Word

infixr 5 <|>
infixr 4 <->

-- | An area of the picture's bacground (See Background) of w columns and h rows.
background_fill :: Int -> Int -> Image
background_fill w h 
    | w == 0    = EmptyImage
    | h == 0    = EmptyImage
    | otherwise = BGFill w h

-- | Combines two images horizontally. Alias for horiz_join
--
-- infixr 5
(<|>) :: Image -> Image -> Image
(<|>) = horiz_join

-- | Combines two images vertically. Alias for vert_join
--
-- infixr 4
(<->) :: Image -> Image -> Image
(<->) = vert_join

-- | Compose any number of images horizontally.
horiz_cat :: [Image] -> Image
horiz_cat = foldr horiz_join EmptyImage

-- | Compose any number of images vertically.
vert_cat :: [Image] -> Image
vert_cat = foldr vert_join EmptyImage

-- | A Data.Text.Lazy value
text :: Attr -> TL.Text -> Image
text a txt
    | TL.length txt == 0 = EmptyImage
    | otherwise          = let display_width = safe_wcswidth (TL.unpack txt)
                           in HorizText a txt display_width (fromIntegral $! TL.length txt)

-- | A Data.Text value
text' :: Attr -> T.Text -> Image
text' a txt
    | T.length txt == 0 = EmptyImage
    | otherwise         = let display_width = safe_wcswidth (T.unpack txt)
                          in HorizText a (TL.fromStrict txt) display_width (T.length txt)

-- | an image of a single character. This is a standard Haskell 31-bit character assumed to be in
-- the ISO-10646 encoding.
char :: Attr -> Char -> Image
char a c =
    let display_width = safe_wcwidth c
    in HorizText a (TL.singleton c) display_width 1

-- | A string of characters layed out on a single row with the same display attribute. The string is
-- assumed to be a sequence of ISO-10646 characters. 
--
-- Note: depending on how the Haskell compiler represents string literals a string literal in a
-- UTF-8 encoded source file, for example, may be represented as a ISO-10646 string. 
-- That is, I think, the case with GHC 6.10. This means, for the most part, you don't need to worry
-- about the encoding format when outputting string literals. Just provide the string literal
-- directly to iso_10646_string or string.
-- 
iso_10646_string :: Attr -> String -> Image
iso_10646_string a str = 
    let display_width = safe_wcswidth str
    in HorizText a (TL.pack str) display_width (length str)

-- | Alias for iso_10646_string. Since the usual case is that a literal string like "foo" is
-- represented internally as a list of ISO 10646 31 bit characters.  
--
-- Note: Keep in mind that GHC will compile source encoded as UTF-8 but the literal strings, while
-- UTF-8 encoded in the source, will be transcoded to a ISO 10646 31 bit characters runtime
-- representation.
string :: Attr -> String -> Image
string = iso_10646_string

-- | A string of characters layed out on a single row. The input is assumed to be the bytes for
-- UTF-8 encoded text.
utf8_string :: Attr -> [Word8] -> Image
utf8_string a bytes = utf8_bytestring a (BL.pack bytes)

-- | Renders a UTF-8 encoded lazy bytestring. 
utf8_bytestring :: Attr -> BL.ByteString -> Image
utf8_bytestring a bs = text a (TL.decodeUtf8 bs)

-- | Renders a UTF-8 encoded strict bytestring. 
utf8_bytestring' :: Attr -> B.ByteString -> Image
utf8_bytestring' a bs = text' a (T.decodeUtf8 bs)

-- | creates a fill of the specified character. The dimensions are in number of characters wide and
-- number of rows high.
char_fill :: Integral d => Attr -> Char -> d -> d -> Image
char_fill _a _c 0  _h = EmptyImage
char_fill _a _c _w 0  = EmptyImage
char_fill a c w h =
    vert_cat $ replicate (fromIntegral h) $ HorizText a txt display_width char_width
    where 
        txt = TL.replicate (fromIntegral w) (TL.singleton c)
        display_width = safe_wcwidth c * (fromIntegral w)
        char_width = fromIntegral w

-- | The empty image. Useful for fold combinators. These occupy no space nor define any display
-- attributes.
empty_image :: Image 
empty_image = EmptyImage

-- | pad the given image. This adds background character fills to the left, top, right, bottom.
-- The pad values are how many display columns or rows to add.
pad :: Int -> Int -> Int -> Int -> Image -> Image
pad 0 0 0 0 i = i
pad in_l in_t in_r in_b in_image
    | in_l < 0 || in_t < 0 || in_r < 0 || in_b < 0 = error "cannot pad by negative amount"
    | otherwise = go in_l in_t in_r in_b in_image
        where 
            -- TODO: uh.
            go 0 0 0 0 i = i
            go 0 0 0 b i = VertJoin i (BGFill w b) w h
                where w = image_width  i
                      h = image_height i + b
            go 0 0 r b i = go 0 0 0 b $ HorizJoin i (BGFill r h) w h
                where w = image_width  i + r
                      h = image_height i
            go 0 t r b i = go 0 0 r b $ VertJoin (BGFill w t) i w h
                where w = image_width  i
                      h = image_height i + t
            go l t r b i = go 0 t r b $ HorizJoin (BGFill l h) i w h
                where w = image_width  i + l
                      h = image_height i

-- | translates an image by padding or cropping the top and left.
--
-- This can have an unexpected effect: Translating an image to less than (0,0) then to greater than
-- (0,0) will crop the image.
translate :: Int -> Int -> Image -> Image
translate x y i = translate_x x (translate_y y i)

-- | translates an image by padding or cropping the left
translate_x :: Int -> Image -> Image
translate_x x i
    | x < 0     = let s = abs x in CropLeft i s (image_width i - s) (image_height i)
    | x == 0    = i
    | otherwise = let h = image_height i in HorizJoin (BGFill x h) i (image_width i + x) h

-- | translates an image by padding or cropping the top
translate_y :: Int -> Image -> Image
translate_y y i
    | y < 0     = let s = abs y in CropTop i s (image_width i) (image_height i - s)
    | y == 0    = i
    | otherwise = let w = image_width i in VertJoin (BGFill w y) i w (image_height i + y)

-- | Ensure an image is no larger than the provided size. If the image is larger then crop the right
-- or bottom.
--
-- This is transformed to a vertical crop from the bottom followed by horizontal crop from the
-- right.
crop :: Int -> Int -> Image -> Image
crop 0 _ _ = EmptyImage
crop _ 0 _ = EmptyImage
crop w h i = crop_bottom h (crop_right w i)

-- | crop the display height. If the image is less than or equal in height then this operation has
-- no effect. Otherwise the image is cropped from the bottom.
crop_bottom :: Int -> Image -> Image
crop_bottom 0 _ = EmptyImage
crop_bottom h in_i
    | h < 0     = error "cannot crop height to less than zero"
    | otherwise = go in_i
        where
            go EmptyImage = EmptyImage
            go i@(CropBottom {cropped_image, output_width, output_height})
                | output_height <= h = i
                | otherwise          = CropBottom cropped_image output_width h
            go i
                | h >= image_height i = i
                | otherwise           = CropBottom i (image_width i) h

-- | ensure the image is no wider than the given width. If the image is wider then crop the right
-- side.
crop_right :: Int -> Image -> Image
crop_right 0 _ = EmptyImage
crop_right w in_i
    | w < 0     = error "cannot crop width to less than zero"
    | otherwise = go in_i
        where
            go EmptyImage = EmptyImage
            go i@(CropRight {cropped_image, output_width, output_height})
                | output_width <= w = i
                | otherwise         = CropRight cropped_image w output_height
            go i
                | w >= image_width i = i
                | otherwise          = CropRight i w (image_height i)

-- | ensure the image is no wider than the given width. If the image is wider then crop the left
-- side.
crop_left :: Int -> Image -> Image
crop_left 0 _ = EmptyImage
crop_left w in_i
    | w < 0     = error "cannot crop the width to less than zero"
    | otherwise = go in_i
        where
            go EmptyImage = EmptyImage
            go i@(CropLeft {cropped_image, left_skip, output_width, output_height})
                | output_width <= w = i
                | otherwise         =
                    let left_skip' = left_skip + output_width - w
                    in CropLeft cropped_image left_skip' w output_height
            go i
                | image_width i <= w = i
                | otherwise          = CropLeft i (image_width i - w) w (image_height i)

-- | crop the display height. If the image is less than or equal in height then this operation has
-- no effect. Otherwise the image is cropped from the top.
crop_top :: Int -> Image -> Image
crop_top 0 _ = EmptyImage
crop_top h in_i
    | h < 0  = error "cannot crop the height to less than zero"
    | otherwise = go in_i
        where
            go EmptyImage = EmptyImage
            go i@(CropTop {cropped_image, top_skip, output_width, output_height})
                | output_height <= h = i
                | otherwise          =
                    let top_skip' = top_skip + output_height - h
                    in CropTop cropped_image top_skip' output_width h
            go i
                | image_height i <= h = i
                | otherwise           = CropTop i (image_height i - h) (image_width i) h

-- | Generic resize. Pads and crops as required to assure the given display width and height.
-- This is biased to pad/crop the right and bottom.
resize :: Int -> Int -> Image -> Image
resize w h i = resize_height h (resize_width w i)

-- | Resize the width. Pads and crops as required to assure the given display width.
-- This is biased to pad/crop the right.
resize_width :: Int -> Image -> Image
resize_width w i = case w `compare` image_width i of
    LT -> crop_right w i
    EQ -> i
    GT -> i <|> BGFill (w - image_width i) (image_height i)

-- | Resize the height. Pads and crops as required to assure the given display height.
-- This is biased to pad/crop the bottom.
resize_height :: Int -> Image -> Image
resize_height h i = case h `compare` image_height i of
    LT -> crop_bottom h i
    EQ -> i
    GT -> i <-> BGFill (image_width i) (h - image_height i)

