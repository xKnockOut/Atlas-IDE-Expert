unit Atlas.Core.Debug.EventBreak;

// Beim nächsten Ereignis anhalten (#856), Kern ohne IDE: liest die Antwort
// von atlas.server.eventHandlers und entscheidet, auf welchen Handlern
// vorübergehende Haltepunkte stehen.
// - Ereignisarten nach dem Namen des Ereignisses (und Before/After bei
//   Datenmengen): Maus, Tastatur, Timer, Fenster, Datenbank, Aktionen,
//   Sonstige.
// - Häufig feuernde Ereignisse (debug.breakOnNextEvent.excluded, Vorgabe
//   OnPaint, OnMouseMove, OnUpdate, dazu Timer unter 100 ms) nur, wenn man
//   sie ausdrücklich einschließt.
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
    Command = 'atlas.server.eventHandlers';
    DefaultExcluded = 'OnPaint, OnMouseMove, OnUpdate';
    /// <summary>Timer, die öfter feuern, zählen als häufig.</summary>
    FastTimerMs = 100;
    /// <summary>Ab so vielen Haltepunkten weist Atlas auf die Dauer hin.</summary>
    ManyBreakpoints = 500;
    AllCategories: TAtlasEventCategories = [TAtlasEventCategory.Mouse, TAtlasEventCategory.Keyboard,
      TAtlasEventCategory.Timer, TAtlasEventCategory.Window, TAtlasEventCategory.Database,
      TAtlasEventCategory.Actions, TAtlasEventCategory.Other];
  public
    /// <summary>Argumente für den Befehl: ["uri"] bzw. [null] ohne Projekt.</summary>
    class function Arguments(const AProjectUri: string): string; static;
    class function ReadAnswer(AJson: TJSONValue; out AAnswer: TAtlasEventAnswer): Boolean; static;
    class function CategoryOf(const AEvent: string): TAtlasEventCategory; static;
    /// <summary>Kommagetrennte Liste aufgeräumt: getrimmt, ohne Leere und Doppelte, Reihenfolge bleibt.</summary>
    class function NormalizeExcluded(const AText: string): string; static;
    class function ExcludedList(const AText: string): TArray<string>; static;
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
  MouseEvents: array[0..19] of string = ('OnClick', 'OnDblClick', 'OnMouseDown', 'OnMouseUp', 'OnMouseMove',
    'OnMouseEnter', 'OnMouseLeave', 'OnMouseWheel', 'OnMouseWheelUp', 'OnMouseWheelDown', 'OnMouseActivate',
    'OnContextPopup', 'OnDragDrop', 'OnDragOver', 'OnStartDrag', 'OnEndDrag', 'OnCellClick', 'OnTitleClick',
    'OnGesture', 'OnTap');
  KeyboardEvents: array[0..3] of string = ('OnKeyDown', 'OnKeyUp', 'OnKeyPress', 'OnShortCut');
  WindowEvents: array[0..14] of string = ('OnShow', 'OnHide', 'OnActivate', 'OnDeactivate', 'OnResize',
    'OnClose', 'OnCloseQuery', 'OnCreate', 'OnDestroy', 'OnPaint', 'OnCanResize', 'OnConstrainedResize',
    'OnAfterMonitorDpiChanged', 'OnBeforeMonitorDpiChanged', 'OnHelp');
  DatabaseEvents: array[0..15] of string = ('OnCalcFields', 'OnNewRecord', 'OnFilterRecord', 'OnPostError',
    'OnDeleteError', 'OnEditError', 'OnUpdateError', 'OnUpdateRecord', 'OnReconcileError', 'OnDataChange',
    'OnStateChange', 'OnUpdateData', 'OnValidate', 'OnGetText', 'OnSetText', 'OnCalcAggregates');
  ActionEvents: array[0..1] of string = ('OnExecute', 'OnUpdate');

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
  Values: TJSONArray;
begin
  Values := TJSONArray.Create;
  try
    if AProjectUri = '' then
      Values.AddElement(TJSONNull.Create)
    else
      Values.Add(AProjectUri);
    Result := Values.ToJSON;
  finally
    Values.Free;
  end;
end;

class function TAtlasEventBreak.ReadAnswer(AJson: TJSONValue; out AAnswer: TAtlasEventAnswer): Boolean;
var
  Root, Item: TJSONObject;
  List: TJSONArray;
  Index: Integer;
  Handler: TAtlasEventHandler;
begin
  AAnswer := Default(TAtlasEventAnswer);
  Result := False;
  if not (AJson is TJSONObject) then
    Exit;
  Root := TJSONObject(AJson);
  if Root.GetValue<Integer>('format', 0) <> 1 then
    Exit;
  AAnswer.Unresolved := Root.GetValue<Integer>('unresolved', 0);
  if Root.TryGetValue<TJSONArray>('handlers', List) then
    for Index := 0 to List.Count - 1 do
    begin
      if not (List.Items[Index] is TJSONObject) then
        Continue;
      Item := TJSONObject(List.Items[Index]);
      Handler := Default(TAtlasEventHandler);
      Handler.Form := Item.GetValue<string>('form', '');
      Handler.Component := Item.GetValue<string>('component', '');
      Handler.ComponentClass := Item.GetValue<string>('componentClass', '');
      Handler.Event := Item.GetValue<string>('event', '');
      Handler.Handler := Item.GetValue<string>('handler', '');
      Handler.Container := Item.GetValue<string>('container', '');
      Handler.Code := SameText(Item.GetValue<string>('origin', ''), 'code');
      Handler.FileName := Item.GetValue<string>('file', '');
      Handler.Line := Item.GetValue<Integer>('line', -1);
      Handler.BreakLine := Item.GetValue<Integer>('bodyLine', -1);
      if Handler.BreakLine < 0 then
        Handler.BreakLine := Handler.Line;
      Handler.Interval := Item.GetValue<Integer>('interval', -1);
      if (Handler.Event <> '') and (Handler.Handler <> '') and (Handler.FileName <> '') and (Handler.Line >= 0) then
        AAnswer.Handlers := AAnswer.Handlers + [Handler];
    end;
  Result := True;
end;

class function TAtlasEventBreak.CategoryOf(const AEvent: string): TAtlasEventCategory;
begin
  if MatchText(AEvent, MouseEvents) then
    Result := TAtlasEventCategory.Mouse
  else if MatchText(AEvent, KeyboardEvents) then
    Result := TAtlasEventCategory.Keyboard
  else if SameText(AEvent, 'OnTimer') then
    Result := TAtlasEventCategory.Timer
  else if MatchText(AEvent, WindowEvents) then
    Result := TAtlasEventCategory.Window
  else if StartsText('Before', AEvent) or StartsText('After', AEvent) or MatchText(AEvent, DatabaseEvents) then
    Result := TAtlasEventCategory.Database
  else if MatchText(AEvent, ActionEvents) then
    Result := TAtlasEventCategory.Actions
  else
    Result := TAtlasEventCategory.Other;
end;

class function TAtlasEventBreak.ExcludedList(const AText: string): TArray<string>;
var
  Part, Name: string;
  Found: Boolean;
  Existing: string;
begin
  Result := nil;
  for Part in AText.Split([',', ';', ' ', #9, #13, #10]) do
  begin
    Name := Trim(Part);
    if Name = '' then
      Continue;
    Found := False;
    for Existing in Result do
      if SameText(Existing, Name) then
        Found := True;
    if not Found then
      Result := Result + [Name];
  end;
end;

class function TAtlasEventBreak.NormalizeExcluded(const AText: string): string;
begin
  Result := string.Join(', ', ExcludedList(AText));
end;

class function TAtlasEventBreak.IsFrequent(const AHandler: TAtlasEventHandler;
  const AExcluded: TArray<string>): Boolean;
begin
  Result := MatchText(AHandler.Event, AExcluded) or
    (SameText(AHandler.Event, 'OnTimer') and (AHandler.Interval >= 0) and (AHandler.Interval < FastTimerMs));
end;

class function TAtlasEventBreak.Select(const AHandlers: TArray<TAtlasEventHandler>;
  const AChoice: TAtlasEventChoice; const AExcluded, AVisibleForms: TArray<string>): TArray<Integer>;
var
  Index: Integer;
  Handler: TAtlasEventHandler;
begin
  Result := nil;
  for Index := 0 to High(AHandlers) do
  begin
    Handler := AHandlers[Index];
    if not (CategoryOf(Handler.Event) in AChoice.Categories) then
      Continue;
    if not AChoice.Frequent and IsFrequent(Handler, AExcluded) then
      Continue;
    case AChoice.Scope of
      TAtlasEventScope.OneForm:
        if not SameText(Handler.Form, AChoice.Form) then
          Continue;
      TAtlasEventScope.VisibleForms:
        if not MatchText(Handler.Form, AVisibleForms) then
          Continue;
    end;
    Result := Result + [Index];
  end;
end;

class function TAtlasEventBreak.Locations(const AHandlers: TArray<TAtlasEventHandler>;
  const ASelected: TArray<Integer>): TArray<TAtlasEventLocation>;
var
  Index, Found: Integer;
  Location: TAtlasEventLocation;
begin
  Result := nil;
  for Index in ASelected do
  begin
    Found := LocationAt(Result, AHandlers[Index].FileName, AHandlers[Index].BreakLine);
    if Found < 0 then
    begin
      Location.FileName := AHandlers[Index].FileName;
      Location.Line := AHandlers[Index].BreakLine;
      Location.Handlers := [Index];
      Result := Result + [Location];
    end
    else
      Result[Found].Handlers := Result[Found].Handlers + [Index];
  end;
end;

class function TAtlasEventBreak.LocationAt(const ALocations: TArray<TAtlasEventLocation>;
  const AFileName: string; ALine: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ALocations) do
    if (ALocations[Index].Line = ALine) and SameText(ALocations[Index].FileName, AFileName) then
      Exit(Index);
  Result := -1;
end;

/// <summary>Letzter Teil eines Ausdrucks: FTimer → FTimer, Self.FTimer → FTimer.</summary>
function LastPart(const AText: string): string;
var
  Dot: Integer;
begin
  Dot := LastDelimiter('.', AText);
  Result := Copy(AText, Dot + 1, MaxInt);
end;

class function TAtlasEventBreak.Identify(const AHandlers: TArray<TAtlasEventHandler>;
  const ALocation: TAtlasEventLocation; const ASenderName: string): Integer;
var
  Index, Found: Integer;
begin
  if Length(ALocation.Handlers) = 1 then
    Exit(ALocation.Handlers[0]);
  Result := -1;
  if ASenderName = '' then
    Exit;
  Found := 0;
  for Index in ALocation.Handlers do
    if SameText(LastPart(AHandlers[Index].Component), ASenderName) then
    begin
      Result := Index;
      Inc(Found);
    end;
  // Derselbe Name zweimal (etwa auf zwei Formularen): offen lassen.
  if Found <> 1 then
    Result := -1;
end;

function Source(const AHandler: TAtlasEventHandler): string;
begin
  if AHandler.Component = '' then
    Result := AHandler.Event
  else
    Result := AHandler.Component + '.' + AHandler.Event;
end;

class function TAtlasEventBreak.Caption(const AHandlers: TArray<TAtlasEventHandler>;
  const ALocation: TAtlasEventLocation; AIdentified: Integer): string;
var
  Index: Integer;
  Sources: TArray<string>;
  Handler: TAtlasEventHandler;
begin
  if (AIdentified >= 0) and (AIdentified <= High(AHandlers)) then
    Handler := AHandlers[AIdentified]
  else if Length(ALocation.Handlers) > 0 then
    Handler := AHandlers[ALocation.Handlers[0]]
  else
    Exit('');
  if (AIdentified >= 0) and (AIdentified <= High(AHandlers)) then
    Result := Source(Handler)
  else
  begin
    Sources := nil;
    for Index in ALocation.Handlers do
      if IndexText(Source(AHandlers[Index]), Sources) < 0 then
        Sources := Sources + [Source(AHandlers[Index])];
    Result := string.Join(' / ', Sources);
  end;
  Result := Result + ' → ' + Handler.Container + '.' + Handler.Handler;
end;

class function TAtlasEventBreak.Forms(const AHandlers: TArray<TAtlasEventHandler>): TArray<string>;
var
  Handler: TAtlasEventHandler;
begin
  Result := nil;
  for Handler in AHandlers do
    if (Handler.Form <> '') and (IndexText(Handler.Form, Result) < 0) then
      Result := Result + [Handler.Form];
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := CompareText(A, B);
      if Result = 0 then
        Result := CompareStr(A, B);
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
    Result := Copy(Result, 2, Length(Result) - 2).Replace('''''', '''');
end;

end.
