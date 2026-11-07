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
    cMaxPerProject = 20;
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
  cEvaluateWords: array[0..2] of string = ('evaluate', 'auswerten', 'inspector');
  cWatchWords: array[0..2] of string = ('watch', 'überwach', 'ueberwach');
  cBreakpointWords: array[0..1] of string = ('breakpoint', 'haltepunkt');

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
  mWord: string;
begin
  for mWord in AWords do
  begin
    if Pos(mWord, AText) > 0 then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function IsAny(const AText: string; const AWords: array of string): Boolean;
var
  mWord: string;
begin
  for mWord in AWords do
  begin
    if AText = mWord then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasDebugDialogs }

class function TAtlasDebugDialogs.DialogOf(const AClassName, ACaption: string): TAtlasDebugDialog;
var
  mText: string;
begin
  // Haltepunkt vor Auswerten: „Ausdruck auswerten“ steht auch im Haltepunktdialog, aber nicht im Titel.
  mText := Fold(AClassName + ' ' + ACaption);
  if ContainsAny(mText, cBreakpointWords) then
  begin
    Result := TAtlasDebugDialog.Breakpoint;
  end
  else if ContainsAny(mText, cWatchWords) then
  begin
    Result := TAtlasDebugDialog.Watch;
  end
  else if ContainsAny(mText, cEvaluateWords) then
  begin
    Result := TAtlasDebugDialog.Evaluate;
  end
  else
  begin
    Result := TAtlasDebugDialog.None;
  end;
end;

class function TAtlasDebugDialogs.CleanLabel(const ALabel: string): string;
begin
  Result := Fold(Trim(StringReplace(ALabel, '&', '', [rfReplaceAll])));
  while (Result <> '') and CharInSet(Result[Length(Result)], [':', '.', ' ']) do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

class function TAtlasDebugDialogs.FieldOf(ADialog: TAtlasDebugDialog; const ALabel: string): TAtlasDebugField;
var
  mText: string;
begin
  Result := TAtlasDebugField.None;
  mText := CleanLabel(ALabel);
  case ADialog of
    TAtlasDebugDialog.Evaluate:
      if (mText = '') or IsAny(mText, ['expression', 'ausdruck']) then
      begin
        Result := TAtlasDebugField.Expression;
      end;
    TAtlasDebugDialog.Watch:
      if IsAny(mText, ['expression', 'ausdruck']) then
      begin
        Result := TAtlasDebugField.Expression;
      end;
    TAtlasDebugDialog.Breakpoint:
      if IsAny(mText, ['condition', 'bedingung']) then
      begin
        Result := TAtlasDebugField.Condition;
      end
      else if IsAny(mText, ['eval expression', 'evaluate expression', 'ausdruck auswerten', 'auswertung']) then
      begin
        Result := TAtlasDebugField.LogExpression;
      end
      else if IsAny(mText, ['filename', 'file name', 'dateiname', 'datei']) then
      begin
        Result := TAtlasDebugField.FileName;
      end
      else if IsAny(mText, ['line number', 'line', 'zeilennummer', 'zeile']) then
      begin
        Result := TAtlasDebugField.LineNumber;
      end;
    TAtlasDebugDialog.None: ;
  end;
end;

class function TAtlasDebugDialogs.Completes(AField: TAtlasDebugField): Boolean;
begin
  Result := AField in [TAtlasDebugField.Expression, TAtlasDebugField.Condition, TAtlasDebugField.LogExpression];
end;

class function TAtlasDebugDialogs.ScopeLine(const ALineText: string): Integer;
var
  mLine: Integer;
begin
  if TryStrToInt(Trim(ALineText), mLine) and (mLine >= 1) then
  begin
    Result := mLine - 1;
  end
  else
  begin
    Result := -1;
  end;
end;

{ TAtlasExpressionEdit }

class function TAtlasExpressionEdit.PrefixAt(const AText: string; ACaret: Integer): string;
var
  mCaret, mStart: Integer;
begin
  mCaret := ACaret;
  if mCaret > Length(AText) then
  begin
    mCaret := Length(AText);
  end;
  if mCaret < 0 then
  begin
    mCaret := 0;
  end;
  mStart := mCaret;
  while (mStart > 0) and TTextChars.IsIdentChar(AText[mStart]) do
  begin
    Dec(mStart);
  end;
  Result := Copy(AText, mStart + 1, mCaret - mStart);
end;

class function TAtlasExpressionEdit.OpensAfter(const AOld, ANew: string; ACaret: Integer): Boolean;
var
  mTyped: Char;
  mPrefix: string;
begin
  Result := False;
  if (Length(ANew) <> Length(AOld) + 1) or (ACaret < 1) or (ACaret > Length(ANew)) then
  begin
    Exit;
  end;
  // Genau das Zeichen vor der Schreibmarke kam dazu, der Rest ist gleich.
  if Copy(ANew, 1, ACaret - 1) + Copy(ANew, ACaret + 1, MaxInt) <> AOld then
  begin
    Exit;
  end;
  mTyped := ANew[ACaret];
  if mTyped = '.' then
  begin
    Exit(True);
  end;
  mPrefix := PrefixAt(ANew, ACaret);
  // Erstes Zeichen eines Bezeichners, keine Zahl.
  Result := (Length(mPrefix) = 1) and not CharInSet(mTyped, ['0'..'9']);
end;

class procedure TAtlasExpressionEdit.Apply(const AText: string; ACaret, APrefixLength: Integer;
  const AInsert: string; out ANewText: string; out ANewCaret: Integer);
var
  mCaret, mStart: Integer;
begin
  mCaret := ACaret;
  if mCaret > Length(AText) then
  begin
    mCaret := Length(AText);
  end;
  if mCaret < 0 then
  begin
    mCaret := 0;
  end;
  mStart := mCaret - APrefixLength;
  if mStart < 0 then
  begin
    mStart := 0;
  end;
  // Den Rest eines Worts hinter der Schreibmarke mit ersetzen, wie im Editor.
  while (mCaret < Length(AText)) and TTextChars.IsIdentChar(AText[mCaret + 1]) do
  begin
    Inc(mCaret);
  end;
  ANewText := Copy(AText, 1, mStart) + AInsert + Copy(AText, mCaret + 1, MaxInt);
  ANewCaret := mStart + Length(AInsert);
end;

{ TAtlasExpressionHistory }

constructor TAtlasExpressionHistory.Create;
begin
  Create(cMaxPerProject);
end;

constructor TAtlasExpressionHistory.Create(AMax: Integer);
begin
  inherited Create;
  FMax := AMax;
  if FMax < 1 then
  begin
    FMax := 1;
  end;
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
  mExpression, mKey: string;
  mOld, mNew: TArray<string>;
  mItem: string;
begin
  mExpression := Trim(AExpression);
  Result := False;
  if mExpression = '' then
  begin
    Exit;
  end;
  mKey := KeyOf(AProject);
  if not FProjects.TryGetValue(mKey, mOld) then
  begin
    mOld := nil;
  end;
  if (Length(mOld) > 0) and (mOld[0] = mExpression) then
  begin
    Exit;
  end;
  mNew := TArray<string>.Create(mExpression);
  for mItem in mOld do
  begin
    if (mItem <> mExpression) and (Length(mNew) < FMax) then
    begin
      mNew := mNew + [mItem];
    end;
  end;
  FProjects.AddOrSetValue(mKey, mNew);
  Result := True;
end;

function TAtlasExpressionHistory.Items(const AProject: string): TArray<string>;
begin
  if not FProjects.TryGetValue(KeyOf(AProject), Result) then
  begin
    Result := nil;
  end;
end;

function TAtlasExpressionHistory.Remove(const AProject, AExpression: string): Boolean;
var
  mKey, mExpression, mItem: string;
  mOld, mNew: TArray<string>;
begin
  Result := False;
  mKey := KeyOf(AProject);
  mExpression := Trim(AExpression);
  if not FProjects.TryGetValue(mKey, mOld) then
  begin
    Exit;
  end;
  mNew := nil;
  for mItem in mOld do
  begin
    if mItem = mExpression then
    begin
      Result := True;
    end
    else
    begin
      mNew := mNew + [mItem];
    end;
  end;
  if not Result then
  begin
    Exit;
  end;
  if Length(mNew) = 0 then
  begin
    FProjects.Remove(mKey);
  end
  else
  begin
    FProjects.AddOrSetValue(mKey, mNew);
  end;
end;

procedure TAtlasExpressionHistory.Clear;
begin
  FProjects.Clear;
end;

function TAtlasExpressionHistory.LoadFromText(const AText: string): Boolean;
var
  mRoot, mProjects: TJSONValue;
  mPair: TJSONPair;
  mValue: TJSONValue;
  mList: TArray<string>;
begin
  Clear;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    Result := mRoot is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    mProjects := TJSONObject(mRoot).GetValue('projects');
    Result := mProjects is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    for mPair in TJSONObject(mProjects) do
    begin
      if not (mPair.JsonValue is TJSONArray) then
      begin
        Continue;
      end;
      mList := nil;
      for mValue in TJSONArray(mPair.JsonValue) do
      begin
        // TJSONNumber erbt von TJSONString.
        if (mValue is TJSONString) and not (mValue is TJSONNumber) and (Trim(mValue.Value) <> '') and
          (Length(mList) < FMax) then
        begin
          mList := mList + [Trim(mValue.Value)];
        end;
      end;
      if Length(mList) > 0 then
      begin
        FProjects.AddOrSetValue(KeyOf(mPair.JsonString.Value), mList);
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

function TAtlasExpressionHistory.ToText: string;
var
  mRoot, mProjects: TJSONObject;
  mList: TJSONArray;
  mKeys: TArray<string>;
  mKey, mItem: string;
begin
  mRoot := TJSONObject.Create;
  try
    mProjects := TJSONObject.Create;
    mRoot.AddPair('projects', mProjects);
    // Feste Reihenfolge: Die Datei ändert sich nur, wenn sich der Verlauf ändert.
    mKeys := FProjects.Keys.ToArray;
    TArray.Sort<string>(mKeys);
    for mKey in mKeys do
    begin
      mList := TJSONArray.Create;
      for mItem in FProjects[mKey] do
      begin
        mList.Add(mItem);
      end;
      mProjects.AddPair(mKey, mList);
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

end.
