unit Atlas.Core.Settings.JsonText;

// atlas.json gezielt ändern (#227): Werte setzen und entfernen, ohne die
// übrige Datei anzufassen. Kommentare (// und /* */), unbekannte Schlüssel,
// Reihenfolge, Einrückung und "$schema" bleiben erhalten; geändert wird nur der
// Text des betroffenen Werts. Neue Schlüssel kommen ans Ende ihres Objekts,
// eingerückt wie ihre Geschwister. Pfade mit Punkt: "compiler.onSave".
// Werte werden als JSON-Text übergeben ("true", "12", "\"de\"", "[\"a\"]").
// Leerraum, Kommentare und Strings überspringt TJsoncScanner aus Atlas.Text,
// derselbe wie beim Server: // endet an LF oder CR.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON;

type
  TAtlasJsonText = class
  public
    /// <summary>Kommentare durch Leerzeichen ersetzt, Kommas vor } und ] entfernt: für
    /// TJSONObject.ParseJSONValue.</summary>
    class function StripComments(const AText: string): string; static;
    /// <summary>Wurzelobjekt oder nil (leer oder ungültig); der Aufrufer gibt es frei.</summary>
    class function Parse(const AText: string): TJSONObject; static;
    /// <summary>Wert an APath als JSON-Text; '' wenn nicht vorhanden.</summary>
    class function ValueAt(ARoot: TJSONObject; const APath: string): string; static;
    /// <summary>Setzt APath auf AJson; fehlende Objekte auf dem Weg entstehen.</summary>
    class function SetValue(const AText, APath, AJson: string): string; static;
    /// <summary>Entfernt APath samt Komma; unverändert, wenn nicht vorhanden.</summary>
    class function Remove(const AText, APath: string): string; static;
    /// <summary>Wendet Änderungen der Reihe nach an: Schlüssel = Pfad, Wert = JSON-Text, '' = entfernen.</summary>
    class function ApplyChanges(const AText: string; const AChanges: TArray<TPair<string, string>>): string; static;
    /// <summary>JSON-Text eines Strings mit Anführungszeichen und Escapes.</summary>
    class function Quote(const AValue: string): string; static;
  end;

implementation

uses
  Atlas.Text.Lines,
  Atlas.Text.Jsonc,
  Atlas.Core.Localization.Language,
  Atlas.Text.Json;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TJsonTextText = (AtlasJsonDoesNotStart, AtlasJsonObjectNotClosed);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TJsonTextText] of string = (
    ('atlas.json beginnt nicht mit einem Objekt',
     'atlas.json: Objekt nicht geschlossen'),
    ('atlas.json does not start with an object',
     'atlas.json: object not closed'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TJsonTextText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

type
  TMember = record
    KeyStart: Integer;
    ValueStart: Integer;
    ValueStop: Integer;
  end;

  TScanner = record
    Text: string;
    procedure SkipSpace(var APos: Integer);
    procedure SkipString(var APos: Integer);
    procedure SkipNested(var APos: Integer);
    procedure SkipValue(var APos: Integer);
    function ReadKey(var APos: Integer): string;
    /// <summary>Überspringt Leerraum und Kommas; True vor einem Schlüssel, AClose auf "}" davor.</summary>
    function NextKey(var APos: Integer; var AClose: Integer): Boolean;
    function ReadMember(var APos: Integer; out AKey: string): TMember;
    /// <summary>Sucht AKey im Objekt ab "{" an AOpen. APrevious: Glied davor bzw. ohne Treffer das
    /// letzte (KeyStart -1, wenn keins); AClose: schließende Klammer; ACount: Zahl der Glieder.</summary>
    function Find(AOpen: Integer; const AKey: string; out AMember, APrevious: TMember;
      out AClose: Integer; out ACount: Integer): Boolean;
    function LineIndent(APos: Integer): string;
    function LineBreak: string;
  end;

  /// <summary>Teile von TAtlasJsonText.SetValue: Pfad APath (Parts) auf Json setzen.</summary>
  TValueSetter = record
    Scanner: TScanner;
    Parts: TArray<string>;
    Json: string;
    LineBreak: string;
    function Run: string;
    /// <summary>True: AMember ist ein Objekt, AOpen steht auf seiner Klammer. Sonst steht der neue Text in
    /// AResult.</summary>
    function Descend(const AMember: TMember; AIndex: Integer; var AOpen: Integer; out AResult: string): Boolean;
    /// <summary>Fehlendes Glied Parts[AIndex] ans Ende des Objekts ab AOpen.</summary>
    function Append(AOpen, AClose, ACount, AIndex: Integer): string;
    function AppendAfterLast(AOpen, AIndex: Integer): string;
  end;

  /// <summary>Teile von TAtlasJsonText.Remove.</summary>
  TValueRemover = record
    Scanner: TScanner;
    /// <summary>Anfang der Zeile vor APos samt Zeilenumbruch davor.</summary>
    function LineStartBefore(APos: Integer): Integer;
    function CutAfterPrevious(const AMember, APrevious: TMember): string;
    function CutFirst(AOpen, AClose: Integer; const AMember: TMember): string;
    function Cut(AOpen, AClose: Integer; const AMember, APrevious: TMember): string;
  end;

procedure TScanner.SkipSpace(var APos: Integer);
begin
  // Offene Blockkommentare toleriert: APos steht dann hinter dem Text.
  TJsoncScanner.SkipSpace(Text, APos);
end;

procedure TScanner.SkipString(var APos: Integer);
begin
  // APos steht auf dem öffnenden Anführungszeichen.
  TJsoncScanner.SkipString(Text, APos);
end;

procedure TScanner.SkipNested(var APos: Integer);
var
  mDepth: Integer;
begin
  mDepth := 0;
  while APos <= Length(Text) do
  begin
    case Text[APos] of
      '"':
        begin
          SkipString(APos);
          Continue;
        end;
      '/':
        if (APos < Length(Text)) and CharInSet(Text[APos + 1], ['/', '*']) then
        begin
          SkipSpace(APos);
          Continue;
        end;
      '{', '[':
        Inc(mDepth);
      '}', ']':
        begin
          Dec(mDepth);
          if mDepth = 0 then
          begin
            Inc(APos);
            Exit;
          end;
        end;
    end;
    Inc(APos);
  end;
end;

procedure TScanner.SkipValue(var APos: Integer);
begin
  SkipSpace(APos);
  if APos > Length(Text) then
  begin
    Exit;
  end;
  if Text[APos] = '"' then
  begin
    SkipString(APos);
  end
  else if CharInSet(Text[APos], ['{', '[']) then
  begin
    SkipNested(APos);
  end
  else
  begin
    // Zahl, true, false, null.
    while (APos <= Length(Text)) and not CharInSet(Text[APos], [',', '}', ']', ' ', #9, #10, #13, '/']) do
    begin
      Inc(APos);
    end;
  end;
end;

function TScanner.ReadKey(var APos: Integer): string;
var
  mStart: Integer;
  mValue: TJSONValue;
begin
  mStart := APos;
  SkipString(APos);
  mValue := TJSONObject.ParseJSONValue(Copy(Text, mStart, APos - mStart));
  try
    if mValue is TJSONString then
    begin
      Result := TJSONString(mValue).Value;
    end
    else
    begin
      Result := Copy(Text, mStart + 1, APos - mStart - 2);
    end;
  finally
    mValue.Free;
  end;
end;

function TScanner.NextKey(var APos: Integer; var AClose: Integer): Boolean;
begin
  SkipSpace(APos);
  while (APos <= Length(Text)) and (Text[APos] = ',') do
  begin
    Inc(APos);
    SkipSpace(APos);
  end;
  Result := (APos <= Length(Text)) and (Text[APos] = '"');
  if (APos <= Length(Text)) and (Text[APos] = '}') then
  begin
    AClose := APos;
  end;
end;

function TScanner.ReadMember(var APos: Integer; out AKey: string): TMember;
begin
  Result.KeyStart := APos;
  AKey := ReadKey(APos);
  SkipSpace(APos);
  if (APos <= Length(Text)) and (Text[APos] = ':') then
  begin
    Inc(APos);
  end;
  SkipSpace(APos);
  Result.ValueStart := APos;
  SkipValue(APos);
  Result.ValueStop := APos;
end;

function TScanner.Find(AOpen: Integer; const AKey: string; out AMember, APrevious: TMember;
  out AClose: Integer; out ACount: Integer): Boolean;
var
  mPos: Integer;
  mMember: TMember;
  mKey: string;
begin
  Result := False;
  AMember := Default(TMember);
  APrevious := Default(TMember);
  APrevious.KeyStart := -1;
  ACount := 0;
  mPos := AOpen + 1;
  AClose := -1;
  while NextKey(mPos, AClose) do
  begin
    mMember := ReadMember(mPos, mKey);
    Inc(ACount);
    if Result then
    begin
      Continue;
    end;
    if mKey = AKey then
    begin
      AMember := mMember;
      Result := True;
    end
    else
    begin
      APrevious := mMember;
    end;
  end;
end;

function TScanner.LineIndent(APos: Integer): string;
var
  mStart, mStop: Integer;
begin
  mStart := APos;
  while (mStart > 1) and not CharInSet(Text[mStart - 1], [#10, #13]) do
  begin
    Dec(mStart);
  end;
  mStop := mStart;
  while (mStop <= Length(Text)) and CharInSet(Text[mStop], [' ', #9]) do
  begin
    Inc(mStop);
  end;
  Result := Copy(Text, mStart, mStop - mStart);
end;

function TScanner.LineBreak: string;
begin
  Result := TTextLines.LineBreakOf(Text);
end;

function Segments(const APath: string): TArray<string>;
begin
  Result := APath.Split(['.']);
end;

/// <summary>Verschachteltes Objekt für fehlende Glieder: "a": { "b": wert }.</summary>
function Nested(const ASegments: TArray<string>; AFrom: Integer; const AJson, AIndent, AStep,
  ALineBreak: string): string;
begin
  if AFrom = High(ASegments) then
  begin
    Exit(TAtlasJsonText.Quote(ASegments[AFrom]) + ': ' + AJson);
  end;
  Result := TAtlasJsonText.Quote(ASegments[AFrom]) + ': {' + ALineBreak + AIndent + AStep +
    Nested(ASegments, AFrom + 1, AJson, AIndent + AStep, AStep, ALineBreak) + ALineBreak + AIndent + '}';
end;

const
  cStep = '  ';

{ TValueSetter }

function TValueSetter.Run: string;
var
  mOpen, mClose, mCount, mIndex: Integer;
  mMember, mPrevious: TMember;
begin
  Result := Scanner.Text;
  mOpen := 1;
  Scanner.SkipSpace(mOpen);
  if (mOpen > Length(Scanner.Text)) or (Scanner.Text[mOpen] <> '{') then
  begin
    raise EArgumentException.Create(UiText(TJsonTextText.AtlasJsonDoesNotStart));
  end;
  for mIndex := 0 to High(Parts) do
  begin
    if not Scanner.Find(mOpen, Parts[mIndex], mMember, mPrevious, mClose, mCount) then
    begin
      Exit(Append(mOpen, mClose, mCount, mIndex));
    end;
    if not Descend(mMember, mIndex, mOpen, Result) then
    begin
      Exit;
    end;
  end;
end;

function TValueSetter.Descend(const AMember: TMember; AIndex: Integer; var AOpen: Integer;
  out AResult: string): Boolean;
var
  mIndent: string;
begin
  Result := False;
  AResult := '';
  if AIndex = High(Parts) then
  begin
    AResult := Copy(Scanner.Text, 1, AMember.ValueStart - 1) + Json + Copy(Scanner.Text, AMember.ValueStop, MaxInt);
  end
  else if Scanner.Text[AMember.ValueStart] = '{' then
  begin
    AOpen := AMember.ValueStart;
    Result := True;
  end
  else
  begin
    // Kein Objekt: durch das verschachtelte ersetzen.
    mIndent := Scanner.LineIndent(AMember.KeyStart);
    AResult := Copy(Scanner.Text, 1, AMember.KeyStart - 1) + Nested(Parts, AIndex, Json, mIndent, cStep, LineBreak) +
      Copy(Scanner.Text, AMember.ValueStop, MaxInt);
  end;
end;

function TValueSetter.Append(AOpen, AClose, ACount, AIndex: Integer): string;
var
  mIndent, mInsert: string;
begin
  if AClose < 0 then
  begin
    raise EArgumentException.Create(UiText(TJsonTextText.AtlasJsonObjectNotClosed));
  end;
  if ACount > 0 then
  begin
    Exit(AppendAfterLast(AOpen, AIndex));
  end;
  mIndent := Scanner.LineIndent(AOpen);
  mInsert := Nested(Parts, AIndex, Json, mIndent + cStep, cStep, LineBreak);
  Result := Copy(Scanner.Text, 1, AOpen) + LineBreak + mIndent + cStep + mInsert + LineBreak + mIndent +
    Copy(Scanner.Text, AClose, MaxInt);
end;

function TValueSetter.AppendAfterLast(AOpen, AIndex: Integer): string;
var
  mProbe, mLast: TMember;
  mClose, mCount, mPos: Integer;
  mIndent, mInsert: string;
begin
  // Letztes Glied suchen (kein Schlüssel heißt #0): Einrückung und Einfügestelle.
  Scanner.Find(AOpen, #0, mProbe, mLast, mClose, mCount);
  mIndent := Scanner.LineIndent(mLast.KeyStart);
  mInsert := Nested(Parts, AIndex, Json, mIndent, cStep, LineBreak);
  // Steht schon ein Komma dahinter (erlaubtes Schlusskomma), dahinter einfügen.
  mPos := mLast.ValueStop;
  Scanner.SkipSpace(mPos);
  if (mPos <= Length(Scanner.Text)) and (Scanner.Text[mPos] = ',') then
  begin
    Result := Copy(Scanner.Text, 1, mPos) + LineBreak + mIndent + mInsert + Copy(Scanner.Text, mPos + 1, MaxInt);
  end
  else
  begin
    Result := Copy(Scanner.Text, 1, mLast.ValueStop - 1) + ',' + LineBreak + mIndent + mInsert +
      Copy(Scanner.Text, mLast.ValueStop, MaxInt);
  end;
end;

{ TValueRemover }

function TValueRemover.LineStartBefore(APos: Integer): Integer;
begin
  Result := APos;
  while (Result > 1) and CharInSet(Scanner.Text[Result - 1], [' ', #9]) do
  begin
    Dec(Result);
  end;
  if (Result > 1) and (Scanner.Text[Result - 1] = #10) then
  begin
    Dec(Result);
  end;
  if (Result > 1) and (Scanner.Text[Result - 1] = #13) then
  begin
    Dec(Result);
  end;
end;

function TValueRemover.CutAfterPrevious(const AMember, APrevious: TMember): string;
var
  mComma, mLineStart: Integer;
begin
  mComma := APrevious.ValueStop;
  Scanner.SkipSpace(mComma);
  mLineStart := LineStartBefore(AMember.KeyStart);
  if (mComma > Length(Scanner.Text)) or (Scanner.Text[mComma] <> ',') or (mLineStart <= mComma) then
  begin
    Result := Copy(Scanner.Text, 1, APrevious.ValueStop - 1) + Copy(Scanner.Text, AMember.ValueStop, MaxInt);
  end
  else
  begin
    Result := Copy(Scanner.Text, 1, mComma - 1) + Copy(Scanner.Text, mComma + 1, mLineStart - mComma - 1) +
      Copy(Scanner.Text, AMember.ValueStop, MaxInt);
  end;
end;

function TValueRemover.CutFirst(AOpen, AClose: Integer; const AMember: TMember): string;
var
  mPos: Integer;
begin
  // Erstes Glied: bis zum nächsten Schlüssel bzw. bis vor die schließende Klammer.
  mPos := AMember.ValueStop;
  Scanner.SkipSpace(mPos);
  if (mPos <= Length(Scanner.Text)) and (Scanner.Text[mPos] = ',') then
  begin
    Inc(mPos);
    Scanner.SkipSpace(mPos);
    Result := Copy(Scanner.Text, 1, AMember.KeyStart - 1) + Copy(Scanner.Text, mPos, MaxInt);
  end
  else
  begin
    // Einziges Glied: Objekt leeren.
    Result := Copy(Scanner.Text, 1, AOpen) + Copy(Scanner.Text, AClose, MaxInt);
  end;
end;

function TValueRemover.Cut(AOpen, AClose: Integer; const AMember, APrevious: TMember): string;
begin
  // Mit Vorgänger: dessen Komma und die Zeile des Schlüssels entfernen; Kommentare dazwischen bleiben.
  if APrevious.KeyStart > 0 then
  begin
    Result := CutAfterPrevious(AMember, APrevious);
  end
  else
  begin
    Result := CutFirst(AOpen, AClose, AMember);
  end;
end;

{ TAtlasJsonText }

class function TAtlasJsonText.Quote(const AValue: string): string;
var
  mValue: TJSONString;
begin
  mValue := TJSONString.Create(AValue);
  try
    // Ohne Option: Umlaute bleiben lesbar (die Dateien sind UTF-8); ToJSON allein schreibt \u-Folgen.
    Result := mValue.ToJSON([]);
  finally
    mValue.Free;
  end;
end;

class function TAtlasJsonText.StripComments(const AText: string): string;
begin
  Result := TJsoncScanner.StripComments(AText);
end;

class function TAtlasJsonText.Parse(const AText: string): TJSONObject;
begin
  Result := TJsonRead.ParseObject(StripComments(AText));
end;

class function TAtlasJsonText.ValueAt(ARoot: TJSONObject; const APath: string): string;
var
  mCurrent: TJSONValue;
  mSegment: string;
begin
  Result := '';
  mCurrent := ARoot;
  for mSegment in Segments(APath) do
  begin
    if not (mCurrent is TJSONObject) then
    begin
      Exit;
    end;
    mCurrent := TJSONObject(mCurrent).GetValue(mSegment);
    if mCurrent = nil then
    begin
      Exit;
    end;
  end;
  Result := mCurrent.ToJSON;
end;

class function TAtlasJsonText.SetValue(const AText, APath, AJson: string): string;
var
  mSetter: TValueSetter;
begin
  mSetter.Scanner.Text := AText;
  if Trim(AText) = '' then
  begin
    mSetter.Scanner.Text := '{' + sLineBreak + '}' + sLineBreak;
  end;
  mSetter.Parts := Segments(APath);
  mSetter.Json := AJson;
  mSetter.LineBreak := mSetter.Scanner.LineBreak;
  Result := mSetter.Run;
end;

class function TAtlasJsonText.ApplyChanges(const AText: string;
  const AChanges: TArray<TPair<string, string>>): string;
var
  mChange: TPair<string, string>;
begin
  Result := AText;
  for mChange in AChanges do
  begin
    if mChange.Value = '' then
    begin
      Result := Remove(Result, mChange.Key);
    end
    else
    begin
      Result := SetValue(Result, mChange.Key, mChange.Value);
    end;
  end;
end;

class function TAtlasJsonText.Remove(const AText, APath: string): string;
var
  mRemover: TValueRemover;
  mParts: TArray<string>;
  mOpen, mClose, mCount, mIndex: Integer;
  mMember, mPrevious: TMember;
begin
  Result := AText;
  mRemover.Scanner.Text := AText;
  mParts := Segments(APath);
  mOpen := 1;
  mRemover.Scanner.SkipSpace(mOpen);
  if (mOpen > Length(AText)) or (AText[mOpen] <> '{') then
  begin
    Exit;
  end;
  for mIndex := 0 to High(mParts) do
  begin
    if not mRemover.Scanner.Find(mOpen, mParts[mIndex], mMember, mPrevious, mClose, mCount) then
    begin
      Exit;
    end;
    if mIndex = High(mParts) then
    begin
      Exit(mRemover.Cut(mOpen, mClose, mMember, mPrevious));
    end;
    if AText[mMember.ValueStart] <> '{' then
    begin
      Exit;
    end;
    mOpen := mMember.ValueStart;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Settings.JsonText', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
