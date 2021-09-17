/++
	This module contains most of the functions you'll need.
	All the 'base' classes, like QWidget are defined in this.
+/
module qui.qui;

import std.datetime.stopwatch;
import utils.misc;
import utils.lists;
import std.conv : to;
import qui.termwrap;

import qui.utils;

/// the default foreground color
const Color DEFAULT_FG = Color.white;
/// the default background color
const Color DEFAULT_BG = Color.black;
/// default active widget cycling key (tab)
const dchar WIDGET_CYCLE_KEY = '\t';

/// Available colors are in this enum
public alias Color = qui.termwrap.Color;
/// Availabe Keys (keyboard) for input
public alias Key = qui.termwrap.Event.Keyboard.Key;
/// Mouse Event
public alias MouseEvent = Event.Mouse;
/// Keyboard Event
public alias KeyboardEvent = Event.Keyboard;

/// mouseEvent function. Return true if the event should be dropped
alias MouseEventFuction = bool delegate(QWidget, MouseEvent);
///keyboardEvent function. Return true if the event should be dropped
alias KeyboardEventFunction = bool delegate(QWidget, KeyboardEvent);
/// resizeEvent function. Return true if the event should be dropped
alias ResizeEventFunction = bool delegate(QWidget);
/// activateEvent function. Return true if the event should be dropped
alias ActivateEventFunction = bool delegate(QWidget, bool);
/// TimerEvent function. Return true if the event should be dropped
alias TimerEventFunction = bool delegate(QWidget, uint);
/// Init function. Return true if the event should be dropped
alias InitFunction = bool delegate(QWidget);
/// UpdateEvent function. Return true if the event should be dropped
alias UpdateEventFunction = bool delegate(QWidget);

/// mask of events subscribed
enum EventMask : uint{
	MousePress = 1, /// mouse clicks/presses. This value matches `MouseEvent.State.Click`
	MouseRelease = 1 << 1, /// mouse releases. This value matches `MouseEvent.State.Release`
	MouseHover = 1 << 2, /// mouse move/hover. This value matches `MouseEvent.State.Hover`
	KeyboardPress = 1 << 3, /// key presses. This value matches `KeyboardEvent.State.Pressed`
	KeyboardRelease = 1 << 4, /// key releases. This value matches `KeyboardEvent.State.Released`
	KeyboardWidgetCycleKey = 1 << 5, /// keyboard events concerning active widget cycling key. Use this in combination with KeyboardPress or KeyboardRelease
	Resize = 1 << 6, /// widget resize. _this is ignored, use `QWidget.requestResize();`_
	Activate = 1 << 7, /// widget activated/deactivated.
	Timer = 1 << 8, /// timer 
	Initialize = 1 << 9, /// initialize
	Update = 1 << 10, /// draw itself. _this is ignored, use `QWidget.requestUpdate();`_
	MouseAll = MousePress | MouseRelease | MouseHover, /// all mouse events
	KeyboardAll = KeyboardPress | KeyboardRelease, /// all keyboard events, this does **NOT** include KeyboardWidgetCycleKey 
	InputAll = MouseAll | KeyboardAll, /// MouseAll and KeyboardAll
	All = uint.max, /// all events (all bits=1)
}

/// A cell on terminal
struct Cell{
	/// character
	dchar c;
	/// foreground and background colors
	Color fg, bg;
}

/// Display buffer
struct Viewport{
private:
	Cell[] _buffer;
	uint _seekX, _seekY;
	uint _width, _height;
	uint _actualWidth;
	uint _offsetX, _offsetY; // these are subtracted, only when seek is set, not after

	/// reset
	void reset(){
		_buffer = [];
		_seekX = 0;
		_seekY = 0;
		_width = 0;
		_height = 0;
		_actualWidth = 0;
		_offsetX = 0;
		_offsetY = 0;
	}

	/// seek position in _buffer calculated from _seekX & _seekY
	@property uint _seek(){
		return _seekX + (_seekY*_actualWidth);
	}
	/// set another DisplayBuffer so that it is a rectangular slice from this
	///
	/// Returns: true if done, false if not
	void _getSlice(Viewport* sub, int x, int y, uint width, uint height){
		sub.reset();
		sub._actualWidth = _actualWidth;
		x -= _offsetX;
		y -= _offsetY;
		if (x > _width || y > _height || width == 0 || height == 0)
			return;
		if (x < 0){
			sub._offsetX = -x;
			x = 0;
		}
		if (y < 0){
			sub._offsetY = -y;
			y = 0;
		}
		if (width + x > _width)
			width = _width - x;
		if (height + y > _height)
			height = _height - y;
		immutable uint buffStart  = x + (y*_actualWidth), buffEnd = buffStart + ((height-1)*_actualWidth) + width;
		// this if shouldnt be necessary, but idk what im doing rn, and dont want segfault:
		if (_buffer.length < buffEnd)
			return;
		sub._width = width;
		sub._height = height;
		sub._buffer = _buffer[buffStart .. buffEnd];
	}
public:
	/// if x and y are at a position where writing can happen
	bool isWritable(uint x, uint y){
		return x >= _offsetX && y >= _offsetY && x < _width + _offsetX && y < _height + _offsetY;
	}
	/// move to a position, will move to 0,0 if coordinate outside bounds
	/// 
	/// Returns: true if done, false if outside bounds
	bool moveTo(uint x, uint y){
		if (!isWritable(x, y)){
			_seekX = 0;
			_seekY = 0;
			return false;
		}
		_seekX = x - _offsetX;
		_seekY = y - _offsetY;
		return true;
	}
	/// Writes a character at current position and move ahead
	/// 
	/// Returns: false if outside writing area
	bool write(dchar c, Color fg, Color bg){
		if (_seekX >= _width || _seekY >= _height)
			return false;
		_buffer[_seek] = Cell(c, fg, bg);
		_seekX ++;
		if (_seekX >= _width){
			_seekX = 0;
			_seekY ++;
		}
		return true;
	}
	/// Writes a string.
	/// 
	/// Returns: number of characters written
	uint write(dstring s, Color fg, Color bg){
		uint r;
		foreach (c; s){
			if (write(c, fg, bg))
				r ++;
			else
				return r;
		}
		return r;
	}
	/// Fills line, starting from current coordinates, with maximum `max` number of chars, if `max>0`
	/// 
	/// Returns: number of characters written
	uint fillLine(dchar c, Color fg, Color bg, uint max=0){
		if (_seekX >= _width || _seekY >= _height)
			return 0;
		uint r = _width - _seekX;
		if (max && r > max)
			r = max;
		_buffer[_seek .. _seek + r][] = Cell(c, fg, bg);
		_seekX += r;
		if (_seekX >= _width){
			_seekX = 0;
			_seekY ++;
		}
		return r;
	}
}

/// Base class for all widgets, including layouts and QTerminal
///
/// Use this as parent-class for new widgets
abstract class QWidget{
private:
	/// stores the position of this widget, relative to it's parent widget's position
	uint _posX, _posY;
	/// width of widget
	uint _width;
	/// height of widget
	uint _height;
	/// scroll
	uint _scrollX, _scrollY;
	/// viewport
	Viewport _view;
	/// stores if this widget is the active widget
	bool _isActive = false;
	/// whether this widget is requesting update
	bool _requestingUpdate;
	/// Whether to call resize before next update
	bool _requestingResize;
	/// the parent widget
	QWidget _parent = null;
	/// if it can make parent change scrolling
	bool _canReqScroll = false;
	/// if this widget is itself a scrollable container
	bool _isScrollableContainer;
	/// Events this widget is subscribed to, see `EventMask`
	uint _eventSub = 0;
	/// whether this widget should be drawn or not.
	bool _show = true;
	/// specifies that how much height (in horizontal layout) or width (in vertical) is given to this widget.  
	/// The ratio of all widgets is added up and height/width for each widget is then calculated using this.
	uint _sizeRatio = 1;

	/// custom onInit event, if not null, it should be called before doing anything else in init();
	InitFunction _customInitEvent;
	/// custom mouse event, if not null, it should be called before doing anything else in mouseEvent.
	MouseEventFuction _customMouseEvent;
	/// custom keyboard event, if not null, it should be called before doing anything else in keyboardEvent.
	KeyboardEventFunction _customKeyboardEvent;
	/// custom resize event, if not null, it should be called before doing anything else in the resizeEvent
	ResizeEventFunction _customResizeEvent;
	/// custom onActivate event, if not null, it should be called before doing anything else in activateEvent
	ActivateEventFunction _customActivateEvent;
	/// custom onTimer event, if not null, it should be called before doing anything else in timerEvent
	TimerEventFunction _customTimerEvent;
	/// custom upedateEvent, if not null, it should be called before doing anything else in updateEvent
	UpdateEventFunction _customUpdateEvent;

	/// Called when it needs to request an update.  
	/// Will not do anything if not subscribed to update events
	void _requestUpdate(){
		_requestingUpdate = true;
		if (_parent)
			_parent.requestUpdate();
	}
	/// Called to request this widget to resize at next update
	/// Will not do anything if not subscribed to resize events
	void _requestResize(){
		_requestingResize = true;
		if (_parent)
			_parent.requestResize();
	}
	/// Called to request cursor to be positioned at x,y
	/// Will do nothing if not active widget
	void _requestCursorPos(int x, int y){
		if (_isActive && _parent)
			_parent.requestCursorPos(x < 0 ? x : _posX + x - _view._offsetX , y < 0 ? y : _posY + y - _view._offsetY);
	}
	/// Called to request scrolling to be adjusted
	void _requestScroll(uint x, uint y){
		if (!_isActive || !_parent || x > _width || y > _height)
			return;
		_parent.requestScroll(x + _posX, y + _posY);
	}

	/// called by parent for initialize event
	void _initializeCall(){
		if (!(_eventSub & EventMask.Initialize))
			return;
		if (!_customInitEvent || !_customInitEvent(this))
			this.initialize();
	}
	/// called by parent for mouseEvent
	void _mouseEventCall(MouseEvent mouse){
		if (!(_eventSub & mouse.state)) // this works coz `EventMask.Mouse*` in `_eventSub` matches `MouseEvent.State` values
			return;
		mouse.x = (mouse.x - cast(int)this._posX) + _view._offsetX; // mouse input comes relative to visible area
		mouse.y = (mouse.y - cast(int)this._posY) + _view._offsetY;
		if (!_customMouseEvent || !_customMouseEvent(this, mouse))
			this.mouseEvent(mouse);
	}
	/// called by parent for keyboardEvent
	void _keyboardEventCall(KeyboardEvent key){
		if (!(_eventSub & key.state)) // this works coz `EventMask.Keyboard*` in `_eventSub` matches `KeyboardEvent.State` values
			return;
		if (!_customKeyboardEvent || !_customKeyboardEvent(this, key))
			this.keyboardEvent(key);
	}
	/// called by parent for resizeEvent
	void _resizeEventCall(){
		_requestingResize = false;
		if (!_customResizeEvent || !_customResizeEvent(this))
			this.resizeEvent();
	}
	/// called by parent for activateEvent
	void _activateEventCall(bool isActive){
		/*if (_isActive == isActive)
			return;*/
		_isActive = isActive;
		if (_eventSub & EventMask.Activate && (!_customActivateEvent || !_customActivateEvent(this, isActive)))
			this.activateEvent(isActive);
	}
	/// called by parent for mouseEvent
	void _timerEventCall(uint msecs){
		if (_eventSub && EventMask.Timer && (!_customTimerEvent || !_customTimerEvent(this, msecs)))
			this.timerEvent(msecs);
	}
	/// called by parent for updateEvent
	void _updateEventCall(){
		if (!_requestingUpdate)
			return;
		_requestingUpdate = false;
		_view.moveTo(_view._offsetX,_view._offsetY);
		if (!_customUpdateEvent || !_customUpdateEvent(this))
			this.updateEvent();
	}
protected:
	/// minimum width
	uint _minWidth;
	/// maximum width
	uint _maxWidth;
	/// minimum height
	uint _minHeight;
	/// maximum height
	uint _maxHeight;

	/// viewport coordinates. (drawable area for widget)
	final @property uint viewportX(){
		return _view._offsetX;
	}
	/// ditto
	final @property uint viewportY(){
		return _view._offsetY;
	}
	/// viewport size. (drawable area for widget)
	final @property uint viewportWidth(){
		return _view._width;
	}
	/// ditto
	final @property uint viewportHeight(){
		return _view._height;
	}

	/// If a coordinate is within writing area, and writing area actually exists
	final bool isWritable(uint x, uint y){
		return _view.isWritable(x,y);
	}

	/// move seek for next write to terminal.  
	/// can only write in between `(_viewX .. _viewX + _viewWidth, _viewY .. _viewX + _viewHeight)`
	/// 
	/// Returns: false if writing to new coordinates not possible
	final bool moveTo(uint newX, uint newY){
		return _view.moveTo(newX, newY);
	}
	/// writes a character on terminal
	/// 
	/// Returns: true if done, false if outside writing area
	final bool write(dchar c, Color fg, Color bg){
		return _view.write(c, fg, bg);
	}
	/// writes a (d)string to terminal. if it does not fit in one line, it is wrapped
	/// 
	/// Returns: number of characters written
	final uint write(dstring s, Color fg, Color bg){
		return _view.write(s, fg, bg);
	}
	/// fill current line with a character. `max` is ignored if `max==0`
	/// 
	/// Returns: number of cells written
	final uint fillLine(dchar c, Color fg, Color bg, uint max = 0){
		return _view.fillLine(c, fg, bg, max);
	}

	/// For cycling between widgets.
	/// 
	/// Returns: whether any cycling happened
	bool cycleActiveWidget(){
		return false;
	}
	/// activate the passed widget if this is actually the correct widget
	/// 
	/// Returns: if it was activated or not
	bool searchAndActivateWidget(QWidget target) {
		if (this == target) {
			this._isActive = true;
			if (this._eventSub & EventMask.Activate)
				this._activateEventCall(true);
			return true;
		}
		return false;
	}

	/// called by itself, to update events subscribed to
	final void eventSubscribe(uint newSub){
		_eventSub = newSub;
		if (_parent)
			_parent.eventSubscribe();
	}
	/// called by children when they want to re-subscribe to events
	void eventSubscribe(){}

	/// to set cursor position on terminal. will only work if this is active widget.  
	/// set x or y or both to negative to hide cursor
	void requestCursorPos(int x, int y){
		_requestCursorPos(x, y);
	}

	/// called to request to scroll
	void requestScroll(uint x, uint y){
		_requestScroll(x, y);
	}

	/// Called to update this widget
	void updateEvent(){}

	/// Called after `_display` has been set and this widget is ready to be used
	void initialize(){}
	/// Called when mouse is clicked with cursor on this widget.
	void mouseEvent(MouseEvent mouse){}
	/// Called when key is pressed and this widget is active.
	void keyboardEvent(KeyboardEvent key){}
	/// Called when widget size is changed, or widget should recalculate it's child widgets' sizes;
	void resizeEvent(){}
	/// called right after this widget is activated, or de-activated, i.e: is made _activeWidget, or un-made _activeWidget
	void activateEvent(bool isActive){}
	/// called often. `msecs` is the msecs since last timerEvent, not accurate
	void timerEvent(uint msecs){}
public:
	/// To request parent to trigger an update event
	void requestUpdate(){
		_requestUpdate();
	}
	/// To request parent to trigger a resize event
	void requestResize(){
		_requestResize();
	}
	/// use to change the custom initialize event
	final @property InitFunction onInitEvent(InitFunction func){
		return _customInitEvent = func;
	}
	/// use to change the custom mouse event
	final @property MouseEventFuction onMouseEvent(MouseEventFuction func){
		return _customMouseEvent = func;
	}
	/// use to change the custom keyboard event
	final @property KeyboardEventFunction onKeyboardEvent(KeyboardEventFunction func){
		return _customKeyboardEvent = func;
	}
	/// use to change the custom resize event
	final @property ResizeEventFunction onResizeEvent(ResizeEventFunction func){
		return _customResizeEvent = func;
	}
	/// use to change the custom activate event
	final @property ActivateEventFunction onActivateEvent(ActivateEventFunction func){
		return _customActivateEvent = func;
	}
	/// use to change the custom timer event
	final @property TimerEventFunction onTimerEvent(TimerEventFunction func){
		return _customTimerEvent = func;
	}
	/// Returns: this widget's parent
	final @property QWidget parent(){
		return _parent;
	}
	/// Returns: true if this widget is the current active widget
	final @property bool isActive(){
		return _isActive;
	}
	/// Returns: EventMask of subscribed events
	final @property uint eventSub(){
		return _eventSub;
	}
	/// size of width (height/width, depending of Layout.Type it is in) of this widget, in ratio to other widgets in that layout
	final @property uint sizeRatio(){
		return _sizeRatio;
	}
	/// ditto
	final @property uint sizeRatio(uint newRatio){
		_sizeRatio = newRatio;
		_requestResize();
		return _sizeRatio;
	}
	/// visibility of the widget. getter
	final @property bool show(){
		return _show;
	}
	/// visibility of the widget. setter
	final @property bool show(bool visibility){
		_show = visibility;
		_requestResize();
		return _show;
	}
	/// horizontal scroll.
	final @property uint scrollX(){
		return _scrollX;
	}
	/// vertical scroll.
	final @property uint scrollY(){
		return _scrollY;
	}
	/// width of widget
	final @property uint width(){
		return _width;
	}
	/// width setter. This will actually do `minWidth=maxWidth=value` and call requestResize
	@property uint width(uint value){
		_minWidth = value;
		_maxWidth = value;
		_requestResize();
		return value;
	}
	/// height of widget
	final @property uint height(){
		return _height;
	}
	/// height setter. This will actually do `minHeight=maxHeight=value` (which will then call `requestResize`)
	@property uint height(uint value){
		_minHeight = value;
		_maxHeight = value;
		_requestResize();
		return value;
	}
	/// minimum width
	@property uint minWidth(){
		return _minWidth;
	}
	/// ditto
	@property uint minWidth(uint value){
		_requestResize();
		return _minWidth = value;
	}
	/// minimum height
	@property uint minHeight(){
		return _minHeight;
	}
	/// ditto
	@property uint minHeight(uint value){
		_requestResize();
		return _minHeight = value;
	}
	/// maximum width
	@property uint maxWidth(){
		return _maxWidth;
	}
	/// ditto
	@property uint maxWidth(uint value){
		_requestResize();
		return _maxWidth = value;
	}
	/// maximum height
	@property uint maxHeight(){
		return _maxHeight;
	}
	/// ditto
	@property uint maxHeight(uint value){
		_requestResize();
		return _maxHeight = value;
	}
}

///Used to place widgets in an order (i.e vertical or horizontal)
class QLayout : QWidget{
private:
	/// array of all the widgets that have been added to this layout
	QWidget[] _widgets;
	/// stores the layout type, horizontal or vertical
	QLayout.Type _type;
	/// stores index of active widget. -1 if none. This is useful only for Layouts. For widgets, this stays 0
	int _activeWidgetIndex = -1;
	/// if it is overflowing
	bool _isOverflowing = false;
	/// Color to fill with in unoccupied space
	Color _fillColor;
	/// Color to fill with when overflowing
	Color _overflowColor;
	/// if it has updated since last resizeEvent
	bool _updatedAfterResize = true;

	/// gets height/width of a widget using it's sizeRatio and min/max-height/width
	uint _calculateWidgetSize(QWidget widget, uint ratioTotal, uint totalSpace, ref bool free){
		immutable uint calculatedSize = cast(uint)((widget._sizeRatio*totalSpace)/ratioTotal);
		if (_type == QLayout.Type.Horizontal){
			free = widget.minWidth == 0 && widget.maxWidth == 0;
			return getLimitedSize(calculatedSize, widget.minWidth, widget.maxWidth);
		}
		free = widget.minHeight == 0 && widget.maxHeight == 0;
		return getLimitedSize(calculatedSize, widget.minHeight, widget.maxHeight);
	}
	
	/// recalculates the size of every widget inside layout
	void _recalculateWidgetsSize(){
		FIFOStack!QWidget widgetStack = new FIFOStack!QWidget;
		uint totalRatio = 0;
		uint totalSpace = _type == QLayout.Type.Horizontal ? _width : _height;
		bool free; // @suppress(dscanner.suspicious.unmodified) shut up vscode
		foreach (widget; _widgets){
			if (!widget._show)
				continue;
			totalRatio += widget._sizeRatio;
			widget._height = getLimitedSize(_height, widget.minHeight, widget.maxHeight);
			widget._width = getLimitedSize(_width, widget.minWidth, widget.maxWidth);
			widgetStack.push(widget);
		}
		// do widgets with size limits
		uint limitWRatio, limitWSize; /// totalRatio, and space used of widgets with limits
		for (int i = 0; i < widgetStack.count; i ++){
			QWidget widget = widgetStack.pop;
			immutable uint space = _calculateWidgetSize(widget, totalRatio, totalSpace, free);
			if (free){
				widgetStack.push(widget);
				continue;
			}
			if (_type == QLayout.Type.Horizontal)
				widget._width = space;
			else
				widget._height = space;
			limitWRatio += widget._sizeRatio;
			limitWSize += space;
		}
		totalSpace -= limitWSize;
		totalRatio -= limitWRatio;
		while (widgetStack.count){
			QWidget widget = widgetStack.pop;
			immutable uint space = _calculateWidgetSize(widget, totalRatio, totalSpace, free);
			if (_type == QLayout.Type.Horizontal)
				widget._width = space;
			else
				widget._height = space;
			totalRatio -= widget._sizeRatio;
			totalSpace -= space;
		}
		.destroy(widgetStack);
	}
protected:
	override void eventSubscribe(){
		_eventSub = 0;
		foreach (widget; _widgets)
			_eventSub |= widget._eventSub;
		if (_eventSub & EventMask.KeyboardAll)
			_eventSub |= EventMask.Activate; // if children can become active, then need activate too
		if (_parent)
			_parent.eventSubscribe();
	}

	/// Recalculates size and position for all visible widgets
	override void resizeEvent(){
		_recalculateWidgetsSize(); // resize everything
		// if parent is scrollable container, and there are no size limits, then grow as needed
		if (_minHeight == 0 && _maxHeight == 0 && _minWidth == 0 && _maxWidth == 0 && 
		_parent && _parent._isScrollableContainer){
			if (_type == Type.Horizontal){
				foreach (widget; _widgets){
					if (_height < widget._height)
						_height = widget._height;
					_width += widget._width;
				}
			}else{
				foreach (widget; _widgets){
					if (_width < widget._width)
						_width = widget._width;
					_height += widget._height;
				}
			}
		}
		_updatedAfterResize = false;
		// now reposition everything, and while at it
		uint previousSpace = 0; /// space taken by widgets before
		uint w, h;
		foreach(widget; _widgets){
			if (!widget._show)
				continue;
			w += widget._width;
			h += widget._height;
			if (_type == QLayout.Type.Horizontal){
				widget._posY = 0;
				widget._posX = previousSpace;
				previousSpace += widget._width;
			}else{
				widget._posX = 0;
				widget._posY = previousSpace;
				previousSpace += widget._height;
			}
		}
		_isOverflowing = w > _width || h > _height;
		if (_isOverflowing){
			foreach (widget; _widgets)
				_view.reset();
		}else{
			foreach (i, widget; _widgets){
				_view._getSlice(&(widget._view), widget._posX, widget._posY, widget._width, widget._height);
				widget._resizeEventCall();
			}
		}
	}
	
	/// Redirects the mouseEvent to the appropriate widget
	override public void mouseEvent(MouseEvent mouse){
		if (_isOverflowing)
			return;
		int index = _activeWidgetIndex;
		if (_type == Type.Horizontal){
			foreach (i, w; _widgets){
				if (w._show && w._posX <= mouse.x && w._posX + w._width > mouse.x){
					index = cast(int)i;
					break;
				}
			}
		}else{
			foreach (i, w; _widgets){
				if (w._show && w._posY <= mouse.y && w._posY + w._height > mouse.y){
					index = cast(int)i;
					break;
				}
			}
		}
		if (index > -1){
			if (index != _activeWidgetIndex && _widgets[index]._eventSub & EventMask.KeyboardAll){
				if (_activeWidgetIndex > -1)
					_widgets[_activeWidgetIndex]._activateEventCall(false);
				_widgets[index]._activateEventCall(true);
			}
			_widgets[index]._mouseEventCall(mouse);
		}
	}

	/// Redirects the keyboardEvent to appropriate widget
	override public void keyboardEvent(KeyboardEvent key){
		if (_isOverflowing)
			return;
		if (_activeWidgetIndex > -1)
			_widgets[_activeWidgetIndex]._keyboardEventCall(key);
	}

	/// override initialize to initliaze child widgets
	override void initialize(){
		foreach (widget; _widgets){
			widget._view.reset();
			widget._initializeCall();
		}
	}

	/// override timer event to call child widgets' timers
	override void timerEvent(uint msecs){
		foreach (widget; _widgets)
			widget._timerEventCall(msecs);
	}

	/// override activate event
	override void activateEvent(bool isActive){
		if (isActive){
			_activeWidgetIndex = -1;
			this.cycleActiveWidget();
		}else if (_activeWidgetIndex > -1)
			_widgets[_activeWidgetIndex]._activateEventCall(isActive);
	}
	
	/// called by parent widget to update
	override void updateEvent(){
		if (!_updatedAfterResize){
			_updatedAfterResize = true;
			Color fill = _isOverflowing ? _overflowColor : _fillColor;
			foreach (y; viewportY .. viewportY + viewportHeight){
				moveTo(viewportX, y);
				fillLine(' ', DEFAULT_FG, fill);
			}
			if (_isOverflowing)
				return;
		}
		foreach(i, widget; _widgets){
			if (widget._show && widget._requestingUpdate)
				widget._updateEventCall();
		}
	}
	/// called to cycle between actveWidgets. This is called by parent widget
	/// 
	/// Returns: true if cycled to another widget, false if _activeWidgetIndex set to -1
	override bool cycleActiveWidget(){
		// check if need to cycle within current active widget
		if (_activeWidgetIndex == -1 || !(_widgets[_activeWidgetIndex].cycleActiveWidget())){
			int lastActiveWidgetIndex = _activeWidgetIndex;
			for (_activeWidgetIndex ++; _activeWidgetIndex < _widgets.length; _activeWidgetIndex ++){
				if ((_widgets[_activeWidgetIndex]._eventSub & EventMask.KeyboardAll) && _widgets[_activeWidgetIndex]._show)
					break;
			}
			if (_activeWidgetIndex >= _widgets.length)
				_activeWidgetIndex = -1;
			
			if (lastActiveWidgetIndex != _activeWidgetIndex){
				if (lastActiveWidgetIndex > -1)
					_widgets[lastActiveWidgetIndex]._activateEventCall(false);
				if (_activeWidgetIndex > -1)
					_widgets[_activeWidgetIndex]._activateEventCall(true);
			}
		}
		return _activeWidgetIndex != -1;
	}

	/// activate the passed widget if it's in the current layout, return if it was activated or not
	override bool searchAndActivateWidget(QWidget target){
		immutable int lastActiveWidgetIndex = _activeWidgetIndex;

		// search and activate recursively
		_activeWidgetIndex = -1;
		foreach (index, widget; _widgets) {
			if ((widget._eventSub & EventMask.KeyboardAll) && widget._show && widget.searchAndActivateWidget(target)){
				_activeWidgetIndex = cast(int)index;
				break;
			}
		}

		// and then manipulate the current layout
		if (lastActiveWidgetIndex != _activeWidgetIndex && lastActiveWidgetIndex > -1)
			_widgets[lastActiveWidgetIndex]._activateEventCall(false);
		return _activeWidgetIndex != -1;
	}

public:
	/// Layout type
	enum Type{
		Vertical,
		Horizontal,
	}
	/// constructor
	this(QLayout.Type type){
		_type = type;
		this._fillColor = DEFAULT_BG;
	}
	/// destructor, kills children
	~this(){
		foreach (child; _widgets)
			.destroy(child);
	}
	/// Color for unoccupied space
	@property Color fillColor(){
		return _fillColor;
	}
	/// ditto
	@property Color fillColor(Color newColor){
		return _fillColor = newColor;
	}
	/// Color to fill with when out of space
	@property Color overflowColor(){
		return _overflowColor;
	}
	/// ditto
	@property Color overflowColor(Color newColor){
		return _overflowColor = newColor;
	}
	/// adds a widget, and makes space for it
	void addWidget(QWidget widget, bool allowScrollControl = false){
		widget._parent = this;
		widget._requestingUpdate = true;
		widget._canReqScroll = allowScrollControl;
		_widgets ~= widget;
		eventSubscribe;
	}
	/// ditto
	void addWidget(QWidget[] widgets){
		foreach (i, widget; widgets){
			widget._parent = this;
			widget._requestingUpdate = true;
		}
		_widgets ~= widgets;
		eventSubscribe();
	}
}

/// Container for widgets to make them scrollable, with optional scrollbars
class ScrollContainer : QWidget{
protected:
	QWidget _widget; /// rthe widget to be scrolled

	bool _scrollbarV, _scrollbarH; /// if vertical and horizontal scrollbars are to be shown
	// current scrolling
	// re-assings display buffer based on _subScrollX/Y
	final void rescroll(){
		if (!_widget)
			return;
		_widget._view.reset();
		_view._getSlice(&(_widget._view), 0, 0, _widget._width, _widget._height);
		_widget._view._offsetX += _widget._scrollX;
		_widget._view._offsetY += _widget._scrollY;
	}

	override void requestScroll(uint x, uint y){
		if (!_widget)
			return;
		_widget._scrollX = x;
		_widget._scrollY = y;
		rescroll();
	}
	
	override void keyboardEvent(KeyboardEvent key){

	}
public:
	/// constructor
	this(){
		this._isScrollableContainer = true;

	}
}

/// A terminal (as the name says).
class QTerminal : QLayout{
private:
	/// To actually access the terminal
	TermWrapper _termWrap;
	/// set to false to stop UI loop in run()
	bool _isRunning;
	/// the key used for cycling active widget
	dchar _activeWidgetCycleKey = WIDGET_CYCLE_KEY;
	/// whether to stop UI loop on Interrupt
	bool _stopOnInterrupt = true;
	/// cursor position
	int _cursorX = -1, _cursorY = -1;

	/// Reads InputEvent and calls appropriate functions to address those events
	void _readEvent(Event event){
		if (event.type == Event.Type.HangupInterrupt){
			if (_stopOnInterrupt)
				_isRunning = false;
			else{ // otherwise read it as a Ctrl+C
				KeyboardEvent keyEvent;
				keyEvent.key = KeyboardEvent.CtrlKeys.CtrlC;
				this._keyboardEventCall(keyEvent);
			}
		}else if (event.type == Event.Type.Keyboard){
			KeyboardEvent kPress = event.keyboard;
			this._keyboardEventCall(kPress);
		}else if (event.type == Event.Type.Mouse){
			this._mouseEventCall(event.mouse);
		}else if (event.type == Event.Type.Resize){
			this._resizeEventCall();
		}
	}

	/// writes _view to _termWrap
	void _flushBuffer(){
		if (_view._buffer.length == 0)
			return;
		Color prevfg = _view._buffer[0].fg, prevbg = _view._buffer[0].bg;
		_termWrap.color(prevfg, prevbg);
		uint x, y;
		foreach (cell; _view._buffer){
			if (cell.fg != prevfg || cell.bg != prevbg){
				prevfg = cell.fg;
				prevbg = cell.bg;
				_termWrap.color(prevfg, prevbg);
			}
			_termWrap.put(x, y, cell.c);
			x ++;
			if (x == _width){
				x = 0;
				y ++;
			}
		}
	}

protected:

	override void eventSubscribe(){
		_eventSub = EventMask.All;
	}

	override void requestCursorPos(int x, int y){
		_cursorX = x;
		_cursorY = y;
	}

	override void resizeEvent(){
		_height = _termWrap.height;
		_width = _termWrap.width;
		_view._buffer.length = _width * _height;
		_view._width = _width;
		_view._actualWidth = _width;
		_view._height = _height;
		super.resizeEvent();
	}

	override void keyboardEvent(KeyboardEvent key){
		if (_isOverflowing)
			return;
		QWidget activeWidget = null;
		uint eSub = 0;
		if (_activeWidgetIndex > -1){
			activeWidget = _widgets[_activeWidgetIndex];
			eSub = activeWidget._eventSub;
		}
		if (key.key == _activeWidgetCycleKey && key.state == KeyboardEvent.State.Pressed &&
		(!activeWidget || !(eSub & EventMask.KeyboardWidgetCycleKey))){
			this.cycleActiveWidget();
			return;
		}
		if (activeWidget)
			activeWidget._keyboardEventCall(key);
	}
	
	override void updateEvent(){
		// resize if needed
		if (_requestingResize)
			this._resizeEventCall();
		_cursorX = -1;
		_cursorY = -1;
		super.updateEvent(); // no, this is not a mistake, dont change this to updateEventCall again!
		// flush _view._buffer to _termWrap
		_flushBuffer();
		// check if need to show/hide cursor
		if (_cursorX < 0 || _cursorY < 0)
			_termWrap.cursorVisible = false;
		else{
			_termWrap.moveCursor(_cursorX, _cursorY);
			_termWrap.cursorVisible = true;
		}
		_termWrap.flush();
	}

public:
	/// time to wait between timer events (milliseconds)
	ushort timerMsecs;
	/// constructor
	this(QLayout.Type displayType = QLayout.Type.Vertical, ushort timerDuration = 500){
		super(displayType);
		timerMsecs = timerDuration;

		_termWrap = new TermWrapper();
		this._isActive = true; // so it can make other widgets active on mouse events
	}
	~this(){
		.destroy(_termWrap);
	}

	/// stops UI loop. **not instant**, if it is in-between updates, event functions, or timers, it will complete those first
	void terminate(){
		_isRunning = false;
	}

	/// whether to stop UI loop on HangupInterrupt (Ctrl+C)
	@property bool terminateOnHangup(){
		return _stopOnInterrupt;
	}
	/// ditto
	@property bool terminateOnHangup(bool newVal){
		return _stopOnInterrupt = newVal;
	}
	
	/// starts the UI loop
	void run(){
		_initializeCall();
		_resizeEventCall();
		_updateEventCall();
		_isRunning = true;
		StopWatch sw = StopWatch(AutoStart.yes);
		while (_isRunning){
			int timeout = cast(int)(timerMsecs - sw.peek.total!"msecs");
			Event event;
			while (_termWrap.getEvent(timeout, event) > 0){
				_readEvent(event);
				timeout = cast(int)(timerMsecs - sw.peek.total!"msecs");
				_updateEventCall();
			}
			if (sw.peek.total!"msecs" >= timerMsecs){
				_timerEventCall(cast(uint)sw.peek.total!"msecs");
				sw.reset;
				sw.start;
				_updateEventCall();
			}
		}
	}

	/// search the passed widget recursively and activate it
	/// 
	/// Returns: true if the widget was made active, false if not found and not done
	bool activateWidget(QWidget target) {
		return this.searchAndActivateWidget(target);
	}

	/// Changes the key used to cycle between active widgets.
	/// 
	/// for `key`, use either ASCII value of keyboard key, or use KeyboardEvent.Key or KeyboardEvent.CtrlKeys
	void setActiveWidgetCycleKey(dchar key){
		_activeWidgetCycleKey = key;
	}
}
