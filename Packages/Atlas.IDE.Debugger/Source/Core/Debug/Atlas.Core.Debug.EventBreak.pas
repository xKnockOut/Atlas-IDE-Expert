unit Atlas.Core.Debug.EventBreak;

// Beim nächsten Ereignis anhalten (#856), Kern ohne IDE: liest die Antwort
// von atlas.server.eventHandlers und entscheidet, auf welchen Handlern
// vorübergehende Haltepunkte stehen.
// - Ereignisarten nach dem Namen des Ereignisses (und Before/After bei
//   Datenmengen): Maus, Tastatur, Timer, Fenster, Datenbank, Aktionen,
//   Sonstige.
// - Häufig feuernde Ereignisse (debug.breakOnNextEvent.excluded, Liste aus
//   Atlas.Core.Settings.EventBreakNames, dazu Timer unter 100 ms) nur, wenn
//   man sie ausdrücklich einschließt.
// - Einschränkung auf ein Formular oder die gerade sichtbaren (deren Klassen
//   ermittelt die IDE-Seite über Screen.Forms).
// - Je Stelle (Datei und Zeile der ersten Anweisung, bodyLine) ein
//   Haltepunkt; teilen sich
//   mehrere Komponenten einen Handler, entscheidet beim Halt Sender.Name.

interface

uses
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  TAtlasEventCategory = (Mouse, Keyboard, Timer, Window, Database, Actions, Other);
  TAtlasEventScope = (AllForms, VisibleForms, OneForm);
  {$SCOPEDENUMS OFF}
  TAtlasEventCategories = set of TAtlasEventCategory;

  TAtlasEventHandler = record
    Form: string;
    Component: string;
    ComponentClass: string;
    Event: string;
    Handler: string;
    Container: string;
    /// <summary>Im Code zugewiesen statt in der Formulardatei.</summary>
    Code: Boolean;
    FileName: string;
    /// <summary>Zeile (ab 0) des begin.</summary>
    Line: Integer;
    /// <summary>Zeile (ab 0) des Haltepunkts: erste Anweisung bzw. end, dort ist Sender schon auswertbar; ohne
    /// Angabe des Servers das begin.</summary>
    BreakLine: Integer;
    /// <summary>Interval in ms; -1 ohne Angabe.</summary>
    Interval: Integer;
  end;

  TAtlasEventAnswer = record
    Handlers: TArray<TAtlasEventHandler>;
    /// <summary>Handler ohne auffindbaren Rumpf.</summary>
    Unresolved: Integer;
  end;

  TAtlasEventChoice = record
    Categories: TAtlasEventCategories;
    /// <summary>Häufige Ereignisse und schnelle Timer einschließen.</summary>
    Frequent: Boolean;
    Scope: TAtlasEventScope;
    /// <summary>Formularklasse bei OneForm.</summary>
    Form: string;
    class function Defaults: TAtlasEventChoice; static;
  end;

  /// <summary>Eine Haltestelle: Datei, Zeile und die Handler (Indizes), die dort beginnen.</summary>
  TAtlasEventLocation = record
    FileName: string;
    Line: Integer;
    Handlers: TArray<Integer>;
  end;

  TAtlasEventBreak = class
  public const
    cCommand = 'atlas.server.eventHandlers';
    /// <summary>Timer, die öfter feuern, zählen als häufig.</summary>
    cFastTimerMs = 100;
    /// <summary>Ab so vielen Haltepunkten weist Atlas auf die Dauer hin.</summary>
    cManyBreakpoints = 500;
    cAllCategories: TAtlasEventCategories = [TAtlasEventCategory.Mouse, TAtlasEventCategory.Keyboard,
      TAtlasEventCategory.Timer, TAtlasEventCategory.Window, TAtlasEventCategory.Database,
      TAtlasEventCategory.Actions, TAtlasEventCategory.Other];
  public
    /// <summary>Argumente für den Befehl: ["uri"] bzw. [null] ohne Projekt.</summary>
    class function Arguments(const AProjectUri: string): string; static;
    class function ReadAnswer(AJson: TJSONValue; out AAnswer: TAtlasEventAnswer): Boolean; static;
    class function CategoryOf(const AEvent: string): TAtlasEventCategory; static;
    /// <summary>Ausgenommenes Ereignis oder Timer unter FastTimerMs.</summary>
    class function IsFrequent(const AHandler: TAtlasEventHandler; const AExcluded: TArray<string>): Boolean;
      static;
    /// <summary>Indizes der Handler, die zur Wahl passen. AVisibleForms gilt nur bei VisibleForms.</summary>
    class function Select(const AHandlers: TArray<TAtlasEventHandler>; const AChoice: TAtlasEventChoice;
      const AExcluded, AVisibleForms: TArray<string>): TArray<Integer>; static;
    /// <summary>Haltestellen der gewählten Handler, je Datei und Zeile eine.</summary>
    class function Locations(const AHandlers: TArray<TAtlasEventHandler>;
      const ASelected: TArray<Integer>): TArray<TAtlasEventLocation>; static;
    /// <summary>Haltestelle an AFileName/ALine; -1 ohne.</summary>
    class function LocationAt(const ALocations: TArray<TAtlasEventLocation>; const AFileName: string;
      ALine: Integer): Integer; static;
    /// <summary>Welcher Handler der Stelle gefeuert hat: der einzige, sonst der mit Komponente ASenderName;
    /// -1, wenn das offen bleibt.</summary>
    class function Identify(const AHandlers: TArray<TAtlasEventHandler>; const ALocation: TAtlasEventLocation;
      const ASenderName: string): Integer; static;
    /// <summary>„btnSpeichern.OnClick → TfrmKunde.btnSpeichernClick“; bei offener Wahl alle Komponenten der Stelle
    /// mit „ / “.</summary>
    class function Caption(const AHandlers: TArray<TAtlasEventHandler>; const ALocation: TAtlasEventLocation;
      AIdentified: Integer): string; static;
    /// <summary>Formularklassen der Handler, sortiert, ohne Doppelte.</summary>
    class function Forms(const AHandlers: TArray<TAtlasEventHandler>): TArray<string>; static;
    /// <summary>Ausdrücke für die sichtbaren Formulare: Anzahl, Klasse und Sichtbarkeit des Formulars AIndex.
    /// </summary>
    class function FormCountExpression: string; static;
    class function FormClassExpression(AIndex: Integer): string; static;
    class function FormVisibleExpression(AIndex: Integer): string; static;
    /// <summary>'TKunde' bzw. TKunde → TKunde.</summary>
    class function Unquote(const AValue: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults;

const
  cMouseEvents: array[0..19] of string = ('OnClick', 'OnDblClick', 'OnMouseDown', 'OnMouseUp', 'OnMouseMove',
    'OnMouseEnter', 'OnMouseLeave', 'OnMouseWheel', 'OnMouseWheelUp', 'OnMouseWheelDown', 'OnMouseActivate',
    'OnContextPopup', 'OnDragDrop', 'OnDragOver', 'OnStartDrag', 'OnEndDrag', 'OnCellClick', 'OnTitleClick',
    'OnGesture', 'OnTap');
  cKeyboardEvents: array[0..3] of string = ('OnKeyDown', 'OnKeyUp', 'OnKeyPress', 'OnShortCut');
  cWindowEvents: array[0..14] of string = ('OnShow', 'OnHide', 'OnActivate', 'OnDeactivate', 'OnResize',
    'OnClose', 'OnCloseQuery', 'OnCreate', 'OnDestroy', 'OnPaint', 'OnCanResize', 'OnConstrainedResize',
    'OnAfterMonitorDpiChanged', 'OnBeforeMonitorDpiChanged', 'OnHelp');
  cDatabaseEvents: array[0..15] of string = ('OnCalcFields', 'OnNewRecord', 'OnFilterRecord', 'OnPostError',
    'OnDeleteError', 'OnEditError', 'OnUpdateError', 'OnUpdateRecord', 'OnReconcileError', 'OnDataChange',
    'OnStateChange', 'OnUpdateData', 'OnValidate', 'OnGetText', 'OnSetText', 'OnCalcAggregates');
  cActionEvents: array[0..1] of string = ('OnExecute', 'OnUpdate');

{ TAtlasEventChoice }

class function TAtlasEventChoice.Defaults: TAtlasEventChoice;
begin
  Result := Default(TAtlasEventChoice);
  Result.Categories := [TAtlasEventCategory.Mouse, TAtlasEventCategory.Keyboard, TAtlasEventCategory.Actions];
  Result.Scope := TAtlasEventScope.AllForms;
end;

{ TAtlasEventBreak }

class function TAtlasEventBreak.Arguments(const AProjectUri: string): string;
var
  mValues: TJSONArray;
begin
  mValues := TJSONArray.Create;
  try
    if AProjectUri = '' then
    begin
      mValues.AddElement(TJSONNull.Create);
    end
    else
    begin
      mValues.Add(AProjectUri);
    end;
    Result := mValues.ToJSON;
  finally
    mValues.Free;
  end;
end;

class function TAtlasEventBreak.ReadAnswer(AJson: TJSONValue; out AAnswer: TAtlasEventAnswer): Boolean;
var
  mRoot, mItem: TJSONObject;
  mList: TJSONArray;
  mIndex: Integer;
  mHandler: TAtlasEventHandler;
begin
  AAnswer := Default(TAtlasEventAnswer);
  Result := False;
  if not (AJson is TJSONObject) then
  begin
    Exit;
  end;
  mRoot := TJSONObject(AJson);
  if mRoot.GetValue<Integer>('format', 0) <> 1 then
  begin
    Exit;
  end;
  AAnswer.Unresolved := mRoot.GetValue<Integer>('unresolved', 0);
  if mRoot.TryGetValue<TJSONArray>('handlers', mList) then
  begin
    for mIndex := 0 to mList.Count - 1 do
    begin
      if not (mList.Items[mIndex] is TJSONObject) then
      begin
        Continue;
      end;
      mItem := TJSONObject(mList.Items[mIndex]);
      mHandler := Default(TAtlasEventHandler);
      mHandler.Form := mItem.GetValue<string>('form', '');
      mHandler.Component := mItem.GetValue<string>('component', '');
      mHandler.ComponentClass := mItem.GetValue<string>('componentClass', '');
      mHandler.Event := mItem.GetValue<string>('event', '');
      mHandler.Handler := mItem.GetValue<string>('handler', '');
      mHandler.Container := mItem.GetValue<string>('container', '');
      mHandler.Code := SameText(mItem.GetValue<string>('origin', ''), 'code');
      mHandler.FileName := mItem.GetValue<string>('file', '');
      mHandler.Line := mItem.GetValue<Integer>('line', -1);
      mHandler.BreakLine := mItem.GetValue<Integer>('bodyLine', -1);
      if mHandler.BreakLine < 0 then
      begin
        mHandler.BreakLine := mHandler.Line;
      end;
      mHandler.Interval := mItem.GetValue<Integer>('interval', -1);
      if (mHandler.Event <> '') and (mHandler.Handler <> '') and (mHandler.FileName <> '') and (mHandler.Line >= 0) then
      begin
        AAnswer.Handlers := AAnswer.Handlers + [mHandler];
      end;
    end;
  end;
  Result := True;
end;

class function TAtlasEventBreak.CategoryOf(const AEvent: string): TAtlasEventCategory;
begin
  if MatchText(AEvent, cMouseEvents) then
  begin
    Result := TAtlasEventCategory.Mouse;
  end
  else if MatchText(AEvent, cKeyboardEvents) then
  begin
    Result := TAtlasEventCategory.Keyboard;
  end
  else if SameText(AEvent, 'OnTimer') then
  begin
    Result := TAtlasEventCategory.Timer;
  end
  else if MatchText(AEvent, cWindowEvents) then
  begin
    Result := TAtlasEventCategory.Window;
  end
  else if StartsText('Before', AEvent) or StartsText('After', AEvent) or MatchText(AEvent, cDatabaseEvents) then
  begin
    Result := TAtlasEventCategory.Database;
  end
  else if MatchText(AEvent, cActionEvents) then
  begin
    Result := TAtlasEventCategory.Actions;
  end
  else
  begin
    Result := TAtlasEventCategory.Other;
  end;
end;

class function TAtlasEventBreak.IsFrequent(const AHandler: TAtlasEventHandler;
  const AExcluded: TArray<string>): Boolean;
begin
  Result := MatchText(AHandler.Event, AExcluded) or
    (SameText(AHandler.Event, 'OnTimer') and (AHandler.Interval >= 0) and (AHandler.Interval < cFastTimerMs));
end;

class function TAtlasEventBreak.Select(const AHandlers: TArray<TAtlasEventHandler>;
  const AChoice: TAtlasEventChoice; const AExcluded, AVisibleForms: TArray<string>): TArray<Integer>;
var
  mIndex: Integer;
  mHandler: TAtlasEventHandler;
begin
  Result := nil;
  for mIndex := 0 to High(AHandlers) do
  begin
    mHandler := AHandlers[mIndex];
    if not (CategoryOf(mHandler.Event) in AChoice.Categories) then
    begin
      Continue;
    end;
    if not AChoice.Frequent and IsFrequent(mHandler, AExcluded) then
    begin
      Continue;
    end;
    case AChoice.Scope of
      TAtlasEventScope.OneForm:
        if not SameText(mHandler.Form, AChoice.Form) then
        begin
          Continue;
        end;
      TAtlasEventScope.VisibleForms:
        if not MatchText(mHandler.Form, AVisibleForms) then
        begin
          Continue;
        end;
      TAtlasEventScope.AllForms: ;
    end;
    Result := Result + [mIndex];
  end;
end;

class function TAtlasEventBreak.Locations(const AHandlers: TArray<TAtlasEventHandler>;
  const ASelected: TArray<Integer>): TArray<TAtlasEventLocation>;
var
  mIndex, mFound: Integer;
  mLocation: TAtlasEventLocation;
begin
  Result := nil;
  for mIndex in ASelected do
  begin
    mFound := LocationAt(Result, AHandlers[mIndex].FileName, AHandlers[mIndex].BreakLine);
    if mFound < 0 then
    begin
      mLocation.FileName := AHandlers[mIndex].FileName;
      mLocation.Line := AHandlers[mIndex].BreakLine;
      mLocation.Handlers := [mIndex];
      Result := Result + [mLocation];
    end
    else
    begin
      Result[mFound].Handlers := Result[mFound].Handlers + [mIndex];
    end;
  end;
end;

class function TAtlasEventBreak.LocationAt(const ALocations: TArray<TAtlasEventLocation>;
  const AFileName: string; ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ALocations) do
  begin
    if (ALocations[mIndex].Line = ALine) and SameText(ALocations[mIndex].FileName, AFileName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Letzter Teil eines Ausdrucks: FTimer → FTimer, Self.FTimer → FTimer.</summary>
function LastPart(const AText: string): string;
var
  mDot: Integer;
begin
  mDot := LastDelimiter('.', AText);
  Result := Copy(AText, mDot + 1, MaxInt);
end;

class function TAtlasEventBreak.Identify(const AHandlers: TArray<TAtlasEventHandler>;
  const ALocation: TAtlasEventLocation; const ASenderName: string): Integer;
var
  mIndex, mFound: Integer;
begin
  if Length(ALocation.Handlers) = 1 then
  begin
    Exit(ALocation.Handlers[0]);
  end;
  Result := -1;
  if ASenderName = '' then
  begin
    Exit;
  end;
  mFound := 0;
  for mIndex in ALocation.Handlers do
  begin
    if SameText(LastPart(AHandlers[mIndex].Component), ASenderName) then
    begin
      Result := mIndex;
      Inc(mFound);
    end;
  end;
  // Derselbe Name zweimal (etwa auf zwei Formularen): offen lassen.
  if mFound <> 1 then
  begin
    Result := -1;
  end;
end;

function Source(const AHandler: TAtlasEventHandler): string;
begin
  if AHandler.Component = '' then
  begin
    Result := AHandler.Event;
  end
  else
  begin
    Result := AHandler.Component + '.' + AHandler.Event;
  end;
end;

class function TAtlasEventBreak.Caption(const AHandlers: TArray<TAtlasEventHandler>;
  const ALocation: TAtlasEventLocation; AIdentified: Integer): string;
var
  mIndex: Integer;
  mSources: TArray<string>;
  mHandler: TAtlasEventHandler;
begin
  if (AIdentified >= 0) and (AIdentified <= High(AHandlers)) then
  begin
    mHandler := AHandlers[AIdentified];
  end
  else if Length(ALocation.Handlers) > 0 then
  begin
    mHandler := AHandlers[ALocation.Handlers[0]];
  end
  else
  begin
    Exit('');
  end;
  if (AIdentified >= 0) and (AIdentified <= High(AHandlers)) then
  begin
    Result := Source(mHandler);
  end
  else
  begin
    mSources := nil;
    for mIndex in ALocation.Handlers do
    begin
      if IndexText(Source(AHandlers[mIndex]), mSources) < 0 then
      begin
        mSources := mSources + [Source(AHandlers[mIndex])];
      end;
    end;
    Result := string.Join(' / ', mSources);
  end;
  Result := Result + ' → ' + mHandler.Container + '.' + mHandler.Handler;
end;

class function TAtlasEventBreak.Forms(const AHandlers: TArray<TAtlasEventHandler>): TArray<string>;
var
  mHandler: TAtlasEventHandler;
begin
  Result := nil;
  for mHandler in AHandlers do
  begin
    if (mHandler.Form <> '') and (IndexText(mHandler.Form, Result) < 0) then
    begin
      Result := Result + [mHandler.Form];
    end;
  end;
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := CompareText(A, B);
      if Result = 0 then
      begin
        Result := CompareStr(A, B);
      end;
    end));
end;

class function TAtlasEventBreak.FormCountExpression: string;
begin
  Result := 'Screen.FormCount';
end;

class function TAtlasEventBreak.FormClassExpression(AIndex: Integer): string;
begin
  Result := Format('Screen.Forms[%d].ClassName', [AIndex]);
end;

class function TAtlasEventBreak.FormVisibleExpression(AIndex: Integer): string;
begin
  Result := Format('Screen.Forms[%d].Visible', [AIndex]);
end;

class function TAtlasEventBreak.Unquote(const AValue: string): string;
begin
  Result := Trim(AValue);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
  begin
    Result := Copy(Result, 2, Length(Result) - 2).Replace('''''', '''');
  end;
end;

end.
