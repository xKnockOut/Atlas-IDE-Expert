unit Atlas.Core.Debug.DialogCompletion;

// Vervollständigung in den Debugger-Dialogen (#538), ohne Fenster und ohne IDE:
//   - TAtlasDebugDialogs erkennt den Dialog an Fensterklasse und Titel
//     (deutsch und englisch: „Auswerten/Ändern“, „Überwachung …“,
//     „… Haltepunkt …“) und das Feld an der Beschriftung davor (Label mit
//     FocusControl): Ausdruck, Bedingung, Log-Ausdruck („Ausdruck auswerten“
//     bzw. „Eval expression“), dazu Dateiname und Zeilennummer eines
//     Haltepunkts für den Gültigkeitsbereich. Die IDE-Schicht liest Klasse,
//     Titel und Beschriftungen und protokolliert sie, damit sich die Erkennung
//     in neuen Delphi-Versionen nachziehen lässt.
//   - TAtlasExpressionEdit: Präfix vor der Schreibmarke, wann die Liste von
//     selbst aufgeht (Buchstabe am Wortanfang oder „.“), und der Text nach dem
//     Übernehmen.
//   - TAtlasExpressionHistory: die letzten 20 Ausdrücke je Projekt, neuester
//     zuerst, ohne Doppelte; als JSON { "projects": { Projekt: [ … ] } }.
// Die Datenquelle für das Popup steht in Atlas.Core.Completion.Providers.Expression.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

{$SCOPEDENUMS ON}

type
  TAtlasDebugDialog = (None, Evaluate, Watch, Breakpoint);

  TAtlasDebugField = (None, Expression, Condition, LogExpression, FileName, LineNumber);

  TAtlasDebugDialogs = class
  public
    /// <summary>Dialog zu Fensterklasse und Titel; None, wenn keiner passt.</summary>
    class function DialogOf(const AClassName, ACaption: string): TAtlasDebugDialog; static;
    /// <summary>Feld zur Beschriftung ALabel in ADialog. Ohne Beschriftung gilt in „Auswerten/Ändern“ das
    /// Eingabefeld als Ausdruck (Delphi 12 und 13 zeigen dort keine).</summary>
    class function FieldOf(ADialog: TAtlasDebugDialog; const ALabel: string): TAtlasDebugField; static;
    /// <summary>Feld, in dem Atlas vervollständigt.</summary>
    class function Completes(AField: TAtlasDebugField): Boolean; static;
    /// <summary>Beschriftung ohne &amp;, Doppelpunkt und Leerraum, klein.</summary>
    class function CleanLabel(const ALabel: string): string; static;
    /// <summary>Zeile (0-basiert) aus dem Feld „Zeilennummer“; -1, wenn es keine Zahl ab 1 enthält.</summary>
    class function ScopeLine(const ALineText: string): Integer; static;
  end;

  TAtlasExpressionEdit = class
  public
    /// <summary>Bezeichner vor ACaret (0-basiert) in AText.</summary>
    class function PrefixAt(const AText: string; ACaret: Integer): string; static;
    /// <summary>Geht die Liste nach der Änderung von AOld zu ANew mit der Schreibmarke ACaret von selbst auf?
    /// Ja, wenn genau ein Zeichen dazukam und es „.“ ist oder einen Bezeichner beginnt.</summary>
    class function OpensAfter(const AOld, ANew: string; ACaret: Integer): Boolean; static;
    /// <summary>ANewText: APrefixLength Zeichen vor ACaret durch AInsert ersetzt; ANewCaret dahinter.</summary>
    class procedure Apply(const AText: string; ACaret, APrefixLength: Integer; const AInsert: string;
      out ANewText: string; out ANewCaret: Integer); static;
  end;

  TAtlasExpressionHistory = class
  public const
    MaxPerProject = 20;
  private
    FProjects: TDictionary<string, TArray<string>>;
    FMax: Integer;
    class function KeyOf(const AProject: string): string; static;
  public
    /// <summary>Höchstens MaxPerProject Einträge je Projekt.</summary>
    constructor Create; overload;
    /// <summary>Höchstens AMax Einträge je Projekt (Fenster „Auswerten“, #784: 50).</summary>
    constructor Create(AMax: Integer); overload;
    destructor Destroy; override;
    /// <summary>AExpression (getrimmt) zuerst; ein gleicher Eintrag rückt nach vorn. Leer bleibt weg.
    /// True, wenn sich etwas geändert hat.</summary>
    function Add(const AProject, AExpression: string): Boolean;
    /// <summary>Neuester zuerst.</summary>
    function Items(const AProject: string): TArray<string>;
    /// <summary>AExpression (getrimmt) entfernen; True, wenn es ihn gab.</summary>
    function Remove(const AProject, AExpression: string): Boolean;
    property Limit: Integer read FMax;
    procedure Clear;
    /// <summary>Liest AText; False bei ungültigem JSON oder falscher Form (dann leer).</summary>
    function LoadFromText(const AText: string): Boolean;
    function ToText: string;
  end;

implementation

uses
  System.JSON,
  Atlas.Text.Chars;

const
  // Teile von Fensterklassen und Titeln; klein verglichen.
  EvaluateWords: array[0..2] of string = ('evaluate', 'auswerten', 'inspector');
  WatchWords: array[0..2] of string = ('watch', 'überwach', 'ueberwach');
  BreakpointWords: array[0..1] of string = ('breakpoint', 'haltepunkt');

/// <summary>Klein geschrieben, Umlaute eingeschlossen; unabhängig vom Gebietsschema („Überwachung“).</summary>
function Fold(const AText: string): string;
begin
  Result := LowerCase(AText);
  Result := StringReplace(Result, 'Ä', 'ä', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ö', 'ö', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ü', 'ü', [rfReplaceAll]);
end;

function ContainsAny(const AText: string; const AWords: array of string): Boolean;
var
  Word: string;
begin
  for Word in AWords do
    if Pos(Word, AText) > 0 then
      Exit(True);
  Result := False;
end;

function IsAny(const AText: string; const AWords: array of string): Boolean;
var
  Word: string;
begin
  for Word in AWords do
    if AText = Word then
      Exit(True);
  Result := False;
end;

{ TAtlasDebugDialogs }

class function TAtlasDebugDialogs.DialogOf(const AClassName, ACaption: string): TAtlasDebugDialog;
var
  Text: string;
begin
  // Haltepunkt vor Auswerten: „Ausdruck auswerten“ steht auch im Haltepunktdialog, aber nicht im Titel.
  Text := Fold(AClassName + ' ' + ACaption);
  if ContainsAny(Text, BreakpointWords) then
    Result := TAtlasDebugDialog.Breakpoint
  else if ContainsAny(Text, WatchWords) then
    Result := TAtlasDebugDialog.Watch
  else if ContainsAny(Text, EvaluateWords) then
    Result := TAtlasDebugDialog.Evaluate
  else
    Result := TAtlasDebugDialog.None;
end;

class function TAtlasDebugDialogs.CleanLabel(const ALabel: string): string;
begin
  Result := Fold(Trim(StringReplace(ALabel, '&', '', [rfReplaceAll])));
  while (Result <> '') and CharInSet(Result[Length(Result)], [':', '.', ' ']) do
    Delete(Result, Length(Result), 1);
end;

class function TAtlasDebugDialogs.FieldOf(ADialog: TAtlasDebugDialog; const ALabel: string): TAtlasDebugField;
var
  Text: string;
begin
  Result := TAtlasDebugField.None;
  Text := CleanLabel(ALabel);
  case ADialog of
    TAtlasDebugDialog.Evaluate:
      if (Text = '') or IsAny(Text, ['expression', 'ausdruck']) then
        Result := TAtlasDebugField.Expression;
    TAtlasDebugDialog.Watch:
      if IsAny(Text, ['expression', 'ausdruck']) then
        Result := TAtlasDebugField.Expression;
    TAtlasDebugDialog.Breakpoint:
      if IsAny(Text, ['condition', 'bedingung']) then
        Result := TAtlasDebugField.Condition
      else if IsAny(Text, ['eval expression', 'evaluate expression', 'ausdruck auswerten', 'auswertung']) then
        Result := TAtlasDebugField.LogExpression
      else if IsAny(Text, ['filename', 'file name', 'dateiname', 'datei']) then
        Result := TAtlasDebugField.FileName
      else if IsAny(Text, ['line number', 'line', 'zeilennummer', 'zeile']) then
        Result := TAtlasDebugField.LineNumber;
  end;
end;

class function TAtlasDebugDialogs.Completes(AField: TAtlasDebugField): Boolean;
begin
  Result := AField in [TAtlasDebugField.Expression, TAtlasDebugField.Condition, TAtlasDebugField.LogExpression];
end;

class function TAtlasDebugDialogs.ScopeLine(const ALineText: string): Integer;
var
  Line: Integer;
begin
  if TryStrToInt(Trim(ALineText), Line) and (Line >= 1) then
    Result := Line - 1
  else
    Result := -1;
end;

{ TAtlasExpressionEdit }

class function TAtlasExpressionEdit.PrefixAt(const AText: string; ACaret: Integer): string;
var
  Caret, Start: Integer;
begin
  Caret := ACaret;
  if Caret > Length(AText) then
    Caret := Length(AText);
  if Caret < 0 then
    Caret := 0;
  Start := Caret;
  while (Start > 0) and TTextChars.IsIdentChar(AText[Start]) do
    Dec(Start);
  Result := Copy(AText, Start + 1, Caret - Start);
end;

class function TAtlasExpressionEdit.OpensAfter(const AOld, ANew: string; ACaret: Integer): Boolean;
var
  Typed: Char;
  Prefix: string;
begin
  Result := False;
  if (Length(ANew) <> Length(AOld) + 1) or (ACaret < 1) or (ACaret > Length(ANew)) then
    Exit;
  // Genau das Zeichen vor der Schreibmarke kam dazu, der Rest ist gleich.
  if Copy(ANew, 1, ACaret - 1) + Copy(ANew, ACaret + 1, MaxInt) <> AOld then
    Exit;
  Typed := ANew[ACaret];
  if Typed = '.' then
    Exit(True);
  Prefix := PrefixAt(ANew, ACaret);
  // Erstes Zeichen eines Bezeichners, keine Zahl.
  Result := (Length(Prefix) = 1) and not CharInSet(Typed, ['0'..'9']);
end;

class procedure TAtlasExpressionEdit.Apply(const AText: string; ACaret, APrefixLength: Integer;
  const AInsert: string; out ANewText: string; out ANewCaret: Integer);
var
  Caret, Start: Integer;
begin
  Caret := ACaret;
  if Caret > Length(AText) then
    Caret := Length(AText);
  if Caret < 0 then
    Caret := 0;
  Start := Caret - APrefixLength;
  if Start < 0 then
    Start := 0;
  // Den Rest eines Worts hinter der Schreibmarke mit ersetzen, wie im Editor.
  while (Caret < Length(AText)) and TTextChars.IsIdentChar(AText[Caret + 1]) do
    Inc(Caret);
  ANewText := Copy(AText, 1, Start) + AInsert + Copy(AText, Caret + 1, MaxInt);
  ANewCaret := Start + Length(AInsert);
end;

{ TAtlasExpressionHistory }

constructor TAtlasExpressionHistory.Create;
begin
  Create(MaxPerProject);
end;

constructor TAtlasExpressionHistory.Create(AMax: Integer);
begin
  inherited Create;
  FMax := AMax;
  if FMax < 1 then
    FMax := 1;
  FProjects := TDictionary<string, TArray<string>>.Create;
end;

destructor TAtlasExpressionHistory.Destroy;
begin
  FProjects.Free;
  inherited;
end;

class function TAtlasExpressionHistory.KeyOf(const AProject: string): string;
begin
  // Ohne Projekt ein eigener Verlauf; Pfade unter Windows ohne Groß-/Kleinschreibung.
  Result := LowerCase(Trim(AProject));
end;

function TAtlasExpressionHistory.Add(const AProject, AExpression: string): Boolean;
var
  Expression, Key: string;
  Old, New: TArray<string>;
  Item: string;
begin
  Expression := Trim(AExpression);
  Result := False;
  if Expression = '' then
    Exit;
  Key := KeyOf(AProject);
  if not FProjects.TryGetValue(Key, Old) then
    Old := nil;
  if (Length(Old) > 0) and (Old[0] = Expression) then
    Exit;
  New := TArray<string>.Create(Expression);
  for Item in Old do
    if (Item <> Expression) and (Length(New) < FMax) then
      New := New + [Item];
  FProjects.AddOrSetValue(Key, New);
  Result := True;
end;

function TAtlasExpressionHistory.Items(const AProject: string): TArray<string>;
begin
  if not FProjects.TryGetValue(KeyOf(AProject), Result) then
    Result := nil;
end;

function TAtlasExpressionHistory.Remove(const AProject, AExpression: string): Boolean;
var
  Key, Expression, Item: string;
  Old, New: TArray<string>;
begin
  Result := False;
  Key := KeyOf(AProject);
  Expression := Trim(AExpression);
  if not FProjects.TryGetValue(Key, Old) then
    Exit;
  New := nil;
  for Item in Old do
    if Item = Expression then
      Result := True
    else
      New := New + [Item];
  if not Result then
    Exit;
  if Length(New) = 0 then
    FProjects.Remove(Key)
  else
    FProjects.AddOrSetValue(Key, New);
end;

procedure TAtlasExpressionHistory.Clear;
begin
  FProjects.Clear;
end;

function TAtlasExpressionHistory.LoadFromText(const AText: string): Boolean;
var
  Root, Projects: TJSONValue;
  Pair: TJSONPair;
  Value: TJSONValue;
  List: TArray<string>;
begin
  Clear;
  Root := TJSONObject.ParseJSONValue(AText);
  try
    Result := Root is TJSONObject;
    if not Result then
      Exit;
    Projects := TJSONObject(Root).GetValue('projects');
    Result := Projects is TJSONObject;
    if not Result then
      Exit;
    for Pair in TJSONObject(Projects) do
    begin
      if not (Pair.JsonValue is TJSONArray) then
        Continue;
      List := nil;
      for Value in TJSONArray(Pair.JsonValue) do
        // TJSONNumber erbt von TJSONString.
        if (Value is TJSONString) and not (Value is TJSONNumber) and (Trim(Value.Value) <> '') and
          (Length(List) < FMax) then
          List := List + [Trim(Value.Value)];
      if Length(List) > 0 then
        FProjects.AddOrSetValue(KeyOf(Pair.JsonString.Value), List);
    end;
  finally
    Root.Free;
  end;
end;

function TAtlasExpressionHistory.ToText: string;
var
  Root, Projects: TJSONObject;
  List: TJSONArray;
  Keys: TArray<string>;
  Key, Item: string;
begin
  Root := TJSONObject.Create;
  try
    Projects := TJSONObject.Create;
    Root.AddPair('projects', Projects);
    // Feste Reihenfolge: Die Datei ändert sich nur, wenn sich der Verlauf ändert.
    Keys := FProjects.Keys.ToArray;
    TArray.Sort<string>(Keys);
    for Key in Keys do
    begin
      List := TJSONArray.Create;
      for Item in FProjects[Key] do
        List.Add(Item);
      Projects.AddPair(Key, List);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

end.
