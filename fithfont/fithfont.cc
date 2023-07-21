#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#define STB_TRUETYPE_IMPLEMENTATION
#define STB_STATIC
#include "stb_truetype.h"

static const uint16_t codePage437[] = {
0x0020, 0x263A, 0x263B, 0x2665, 0x2666, 0x2663, 0x2660, 0x2022, 0x25d8, 0x25c8, 0x25d9, 0x2642, 0x2640, 0x266a, 0x266b, 0x263c,
0x25ba, 0x25c4, 0x2195, 0x203c, 0x00b6, 0x00a7, 0x25ac, 0x21ab, 0x2191, 0x2193, 0x2192, 0x2190, 0x221f, 0x2194, 0x25b2, 0x25bc,
0x0020, '!',  '\"',  '#',  '$',  '%',  '&',  '\'',  '(',  ')',  '*',  '+',  ',',  '-',  '.',  '/',
'0',  '1',  '2',  '3',  '4',  '5',  '6',  '7',  '8',  '9',  ':',  ';',  '<',  '=',  '>',  '?',
'@',  'A',  'B',  'C',  'D',  'E',  'F',  'G',  'H',  'I',  'J',  'K',  'L',  'M',  'N',  'O',
'P',  'Q',  'R',  'S',  'T',  'U',  'V',  'W',  'X',  'Y',  'Z',  '[',  '\\',  ']',  '^',  '_',
'`',  'a',  'b',  'c',  'd',  'e',  'f',  'g',  'h',  'i',  'j',  'k',  'l',  'm',  'n',  'o',
'p',  'q',  'r',  's',  't',  'u',  'v',  'w',  'x',  'y',  'z',  '{',  '|',  '}',  '~',  0x2302,
0x00c7, 0x00fc, 0x00e9, 0x00e2, 0x00e4, 0x00e0, 0x00e5, 0x00e7, 0x00ea, 0x00eb, 0x00e8, 0x00ef, 0x00ee, 0x00ec, 0x00c4, 0x00c5,
0x00c9, 0x00e6, 0x00c6, 0x00f4, 0x00f6, 0x00f2, 0x00fb, 0x00f9, 0x00ff, 0x00d6, 0x00dc, 0x00a2, 0x00a3, 0x00a5, 0x20a7, 0x0192,
0x00e1, 0x00ed, 0x00f3, 0x00fa, 0x00f1, 0x00d1, 0x00aa, 0x00ba, 0x00bf, 0x2310, 0x00ac, 0x00bd, 0x00bc, 0x00a1, 0x00ab, 0x00bb,
0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556, 0x2555, 0x2563, 0x2551, 0x2557, 0x255d, 0x255c, 0x255b, 0x2510,
0x2514, 0x2534, 0x252c, 0x251c, 0x2500, 0x253c, 0x255e, 0x255f, 0x255a, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256c, 0x2567,
0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256b, 0x256a, 0x2518, 0x250c, 0x2588, 0x2584, 0x258c, 0x2590, 0x2580,
0x03b1, 0x00df, 0x0393, 0x03c0, 0x03a3, 0x03c3, 0x00b5, 0x03c4, 0x03a6, 0x0398, 0x03a9, 0x03b4, 0x221e, 0x03c6, 0x03b5, 0x2229,
0x2261, 0x00b1, 0x2265, 0x2264, 0x2320, 0x2321, 0x00f7, 0x2248, 0x00b0, 0x2219, 0x00b7, 0x221a, 0x207f, 0x00b2, 0x25a0, 0x00a0,
};

#define FW	8
#define FH	16

#define FONT_NAME	"Px437_IBM_VGA_8x16.ttf"

uint8_t ttf_buffer[1<<25];
uint8_t bmap[8 * 16];

int main(int argc, char **argv)
{
	int			   w = 0, h = 0, i = 0, j = 0;
	int				xoff = 0, yoff = 0;
	stbtt_fontinfo font;
	unsigned char *bitmap;

	fread(ttf_buffer, 1, 1 << 25, fopen(argc > 3 ? argv[3] : FONT_NAME, "rb"));

	stbtt_InitFont(&font, ttf_buffer, stbtt_GetFontOffsetForIndex(ttf_buffer, 0));
	float ys = stbtt_ScaleForPixelHeight( &font, FH );

	int x0, y0, x1, y1;
	stbtt_GetFontBoundingBox(&font, &x0, &y0, &x1, &y1);

	int baseline = ys * -y0;
	fprintf( stdout, "\\ ys: %f  x0: %d y0: %d x1: %d y1: %d baseline: %d\n", ys, x0, y0, x1, y1, baseline );

	for (int cpi = 0; cpi <= 0xFF; cpi++)
	{
		uint16_t codepoint = codePage437[cpi];
		bitmap = stbtt_GetCodepointBitmap(&font, 0, stbtt_ScaleForPixelHeight(&font, FH), codePage437[cpi], &w, &h, &xoff, &yoff);

		// fprintf( stdout, "w: %d h: %d xo: %d yo: %d\n", w, h, xoff, yoff );
		if ( (cpi & 1) == 0 )
		{
			fprintf( stdout, "\n" );
		}

		memset(bmap, 0, 8*16);

		for (j = 0; j < h; ++j)
		{
			for (i = 0; i < w; ++i)
			{
				bmap[(xoff + i) + (yoff + (16 - baseline) + j) * 8] = bitmap[i + w * j];
			}
		}

		uint64_t cval0 = 0;
		uint64_t cval1 = 0;

		for (j = 0; j < 16; ++j)
		{
			for (i = 0; i < 8; ++i)
			{
				uint32_t bit = i + j * 8;
				uint32_t bv = (bmap[bit] > 32 ? 1 : 0);
				// fprintf( stdout, "%c", bv ? '@' : ' ' );

				if (bit < 64)
				{
					cval0 |= (uint64_t)bv << bit;
				}
				else
				{
					cval1 |= (uint64_t)bv << (bit - 64);
				}
			}
			// fprintf( stdout, "\n" );
		}

		fprintf( stdout, "$%016llX , $%016llX , ", cval0, cval1 );
		if (bitmap) free(bitmap);
	}

	return 0;
}
