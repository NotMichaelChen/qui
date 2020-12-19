﻿/++
	Contains functions that might be useful in making new widgets, 
	like for formatting text.
+/
module qui.utils;

import qui.qui;

import utils.baseconv;
import utils.misc;
import std.conv : to;

/// To scroll a line, by an xOffset
/// 
/// Can be used to scroll to right, or to left (by making xOffset negative).  
/// Can also be used to fill an empty line with empty space (`' '`) to make it fill width, if `line.length < width`
/// 
/// Arguments:
/// * `line` is the full line  
/// * `xOffset` is the number of characters scrolled right  
/// * `width` is the number of characters that are to be displayed
/// 
/// Returns: the text that should be displayed
dstring scrollHorizontal(dstring line, integer xOffset, uinteger width){
	dchar[] r;
	if (xOffset == 0){
		// in case it has to do nothing, 
		r = cast(dchar[])line[0 .. width > line.length ? line.length : width].dup;
	}else if (xOffset > 0){
		// only do something if it's not scrolled too far for the line to be even displayed
		if (xOffset < line.length){
			r = cast(dchar[])line[xOffset .. line.length].dup;
		}
	}else if (xOffset < 0){
		// only do something if it's not scrolled too far for the line to be even displayed
		if (cast(integer)(line.length) + xOffset > 0){
			r.length = xOffset * -1;
			r[] = ' ';
			r = r ~ cast(dchar[])line.dup;
		}
	}
	if (r.length < width){
		uinteger filledLength = r.length;
		r.length = width;
		r[filledLength .. r.length] = ' ';
	}else if (r.length > width){
		r.length = width;
	}
	return cast(dstring)r;
}
/// 
unittest{
	assert("0123456789".scrollHorizontal(5, 2) == "56");
	assert("0123456789".scrollHorizontal(0,10) == "0123456789");
	assert("0123456789".scrollHorizontal(10,4) == "    ");
	assert("0123456789".scrollHorizontal(-5,4) == "    ");
	assert("0123456789".scrollHorizontal(-5,6) == "     0");
	assert("0123456789".scrollHorizontal(-1,11) == " 0123456789");
	assert("0123456789".scrollHorizontal(-5,10) == "     01234");
}

/// ditto
dchar[] scrollHorizontal(dchar[] line, integer xOffset, uinteger width){
	return cast(dchar[])(cast(dstring)line).scrollHorizontal(xOffset, width);
}
/// ditto
char[] scrollHorizontal(char[] line, integer xOffset, uinteger width){
	return cast(char[])(cast(dstring)line).scrollHorizontal(xOffset, width);
}

/// Adjusts offset (aka _scrollX or _scrollY) in scrolling so the selected character is visible TODO: FIX THIS
/// 
/// Arguemnts:
/// * `selected` is the character on which the cursor is. If it's >lineWidth, `selected=lineWidth`
/// * `size` is the width/height (depending on if it's horizontal or vertical scrolling) of the space where the line is to be displayed
/// * `offset` is the variable storing the offset (_xOffset or _yOffset)
void adjustScrollingOffset(ref uinteger selected, uinteger size, uinteger lineWidth, ref uinteger offset){
	// if selected is outside size, it shouldn't be
	if (selected > lineWidth){
		selected = lineWidth;
	}
	// range of characters' index that's visible (1 is inclusive, 2 is not)
	uinteger visible1, visible2;
	visible1 = offset;
	visible2 = offset + size;
	if (selected < visible1 || selected >= visible2){
		if (selected < visible1){
			// scroll back
			offset = selected;
		}else if (selected >= visible2){
			// scroll ahead
			offset = selected+1 - (size);
		}
	}
}

/// Center-aligns text
/// 
/// If `text.length > width`, the exceeding characters are removed
/// 
/// Returns: the text center aligned in a string
dstring centerAlignText(dstring text, uinteger width, dchar fill = ' '){
	dchar[] r;
	if (text.length < width){
		r.length = width;
		uinteger offset = (width - text.length)/2;
		r[0 .. offset] = fill;
		r[offset .. offset+text.length][] = text;
		r[offset+text.length .. r.length] = fill;
	}else{
		r = cast(dchar[])text[0 .. width].dup;
	}
	return cast(dstring)r;
}
///
unittest{
	assert("qwr".centerAlignText(7) == "  qwr  ");
}

/// To calculate size of widgets using their sizeRatio
uinteger ratioToRaw(uinteger selectedRatio, uinteger ratioTotal, uinteger total){
	uinteger r;
	r = cast(uinteger)((cast(float)selectedRatio/cast(float)ratioTotal)*total);
	return r;
}

/// gets height/width of a widget using it's sizeRatio and min/max-height/width
uinteger calculateWidgetSize(QLayout.Type type)(QWidget widget, uinteger ratioTotal, uinteger totalSpace, ref bool free){
	Size wSize = widget.size;
	immutable calculatedSize = cast(uinteger)((widget.sizeRatio*totalSpace)/ratioTotal);
	static if (type == QLayout.Type.Horizontal){
		wSize.width = calculatedSize;
		free = wSize.minWidth == 0 && wSize.maxWidth == 0;
		return wSize.width;
	}else{ // this else just exists to shut up compiler about "statement not reachable"
		wSize.height = calculatedSize;
		free = wSize.minHeight == 0 && wSize.maxHeight == 0;
		return wSize.height;
	}
}