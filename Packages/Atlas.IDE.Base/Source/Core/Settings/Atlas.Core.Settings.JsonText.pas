unit Atlas.Core.Settings.JsonText;

// atlas.json gezielt ändern (#227): Werte setzen und entfernen, ohne die
// übrige Datei anzufassen. Kommentare (// und /* */), unbekannte Schlüssel,
// Reihenfolge, Einrückung und "$schema" bleiben erhalten; geändert wird nur der
// Text des betroffenen Werts. Neue Schlüssel kommen ans Ende ihres Objekts,
// eingerückt wie ihre Geschwister. Pfade mit Punkt: "compiler.onSave".
// Werte werden als JSON-Text übergeben ("true", "12", "\"de\"", "[\"a\"]").
// Leerraum, Kommentare und Strings überspringt TJsoncScanner aus Atlas.Text,
// derselbe wie beim Server (ADR 0012): // endet an LF oder CR.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON;

type
  TAtlasJsonText = class
  public
    /// <summary>Kommentare durch Leerzeichen ersetzt, Kommas vor } und ] entfernt: für TJSONObject.ParseJSONValue.</summary>
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
  Atlas.Text.Jsonc;

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
    procedure SkipValue(var APos: Integer);
    function ReadKey(var APos: Integer): string;
    /// <summary>Sucht AKey im Objekt ab "{" an AOpen. APrevious: Glied davor bzw. ohne Treffer das
    /// letzte (KeyStart -1, wenn keins); AClose: schließende Klammer; ACount: Zahl der Glieder.</summary>
    function Find(AOpen: Integer; const AKey: string; out AMember, APrevious: TMember;
      out AClose: Integer; out ACount: Integer): Boolean;
    function LineIndent(APos: Integer): string;
    function LineBreak: string;
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

procedure TScanner.SkipValue(var APos: Integer);
var
  Depth: Integer;
begin
  SkipSpace(APos);
  if APos > Length(Text) then
    Exit;
  if Text[APos] = '"' then
  begin
    SkipString(APos);
    Exit;
  end;
  if CharInSet(Text[APos], ['{', '[']) then
  begin
    Depth := 0;
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
          Inc(Depth);
        '}', ']':
          begin
            Dec(Depth);
            if Depth = 0 then
            begin
              Inc(APos);
              Exit;
            end;
          end;
      end;
      Inc(APos);
    end;
    Exit;
  end;
  // Zahl, true, false, null.
  while (APos <= Length(Text)) and not CharInSet(Text[APos], [',', '}', ']', ' ', #9, #10, #13, '/']) do
    Inc(APos);
end;

function TScanner.ReadKey(var APos: Integer): string;
var
  Start: Integer;
  Value: TJSONValue;
begin
  Start := APos;
  SkipString(APos);
  Value := TJSONObject.ParseJSONValue(Copy(Text, Start, APos - Start));
  try
    if Value is TJSONString then
      Result := TJSONString(Value).Value
    else
      Result := Copy(Text, Start + 1, APos - Start - 2);
  finally
    Value.Free;
  end;
end;

function TScanner.Find(AOpen: Integer; const AKey: string; out AMember, APrevious: TMember;
  out AClose: Integer; out ACount: Integer): Boolean;
var
  Pos: Integer;
  Member: TMember;
  Key: string;
begin
  Result := False;
  AMember := Default(TMember);
  APrevious := Default(TMember);
  APrevious.KeyStart := -1;
  ACount := 0;
  Pos := AOpen + 1;
  AClose := -1;
  while Pos <= Length(Text) do
  begin
    SkipSpace(Pos);
    if Pos > Length(Text) then
      Break;
    if Text[Pos] = '}' then
    begin
      AClose := Pos;
      Exit;
    end;
    if Text[Pos] = ',' then
    begin
      Inc(Pos);
      Continue;
    end;
    if Text[Pos] <> '"' then
      Break;
    Member.KeyStart := Pos;
    Key := ReadKey(Pos);
    SkipSpace(Pos);
    if (Pos <= Length(Text)) and (Text[Pos] = ':') then
      Inc(Pos);
    SkipSpace(Pos);
    Member.ValueStart := Pos;
    SkipValue(Pos);
    Member.ValueStop := Pos;
    Inc(ACount);
    if not Result and (Key = AKey) then
    begin
      AMember := Member;
      Result := True;
    end
    else if not Result then
      APrevious := Member;
  end;
  if Result and (APrevious.KeyStart = 0) then
    APrevious.KeyStart := -1;
end;

function TScanner.LineIndent(APos: Integer): string;
var
  Start, Stop: Integer;
begin
  Start := APos;
  while (Start > 1) and not CharInSet(Text[Start - 1], [#10, #13]) do
    Dec(Start);
  Stop := Start;
  while (Stop <= Length(Text)) and CharInSet(Text[Stop], [' ', #9]) do
    Inc(Stop);
  Result := Copy(Text, Start, Stop - Start);
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
function Nested(const ASegments: TArray<string>; AFrom: Integer; const AJson, AIndent, AStep, ALineBreak: string): string;
begin
  if AFrom = High(ASegments) then
    Exit(TAtlasJsonText.Quote(ASegments[AFrom]) + ': ' + AJson);
  Result := TAtlasJsonText.Quote(ASegments[AFrom]) + ': {' + ALineBreak + AIndent + AStep +
    Nested(ASegments, AFrom + 1, AJson, AIndent + AStep, AStep, ALineBreak) + ALineBreak + AIndent + '}';
end;

{ TAtlasJsonText }

class function TAtlasJsonText.Quote(const AValue: string): string;
var
  Value: TJSONString;
begin
  Value := TJSONString.Create(AValue);
  try
    // Ohne Option: Umlaute bleiben lesbar (die Dateien sind UTF-8); ToJSON allein schreibt \u-Folgen.
    Result := Value.ToJSON([]);
  finally
    Value.Free;
  end;
end;

class function TAtlasJsonText.StripComments(const AText: string): string;
begin
  Result := TJsoncScanner.StripComments(AText);
end;

class function TAtlasJsonText.Parse(const AText: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Result := nil;
  if Trim(AText) = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(StripComments(AText));
  if Value is TJSONObject then
    Result := TJSONObject(Value)
  else
    Value.Free;
end;

class function TAtlasJsonText.ValueAt(ARoot: TJSONObject; const APath: string): string;
var
  Current: TJSONValue;
  Segment: string;
begin
  Result := '';
  Current := ARoot;
  for Segment in Segments(APath) do
  begin
    if not (Current is TJSONObject) then
      Exit;
    Current := TJSONObject(Current).GetValue(Segment);
    if Current = nil then
      Exit;
  end;
  Result := Current.ToJSON;
end;

class function TAtlasJsonText.SetValue(const AText, APath, AJson: string): string;
const
  Step = '  ';
var
  Scanner: TScanner;
  Parts: TArray<string>;
  Open, Close, Count, Index, Pos: Integer;
  Member, Previous, Probe, Dummy: TMember;
  Indent, Insert, LB: string;
begin
  Result := AText;
  if Trim(Result) = '' then
    Result := '{' + sLineBreak + '}' + sLineBreak;
  Scanner.Text := Result;
  LB := Scanner.LineBreak;
  Parts := Segments(APath);
  Open := 1;
  Scanner.SkipSpace(Open);
  if (Open > Length(Result)) or (Result[Open] <> '{') then
    raise EArgumentException.Create('atlas.json beginnt nicht mit einem Objekt');
  for Index := 0 to High(Parts) do
  begin
    if Scanner.Find(Open, Parts[Index], Member, Previous, Close, Count) then
    begin
      if Index = High(Parts) then
        Exit(Copy(Result, 1, Member.ValueStart - 1) + AJson + Copy(Result, Member.ValueStop, MaxInt));
      if Result[Member.ValueStart] = '{' then
      begin
        Open := Member.ValueStart;
        Continue;
      end;
      // Kein Objekt: durch das verschachtelte ersetzen.
      Indent := Scanner.LineIndent(Member.KeyStart);
      Insert := Nested(Parts, Index, AJson, Indent, Step, LB);
      Exit(Copy(Result, 1, Member.KeyStart - 1) + Insert + Copy(Result, Member.ValueStop, MaxInt));
    end;
    // Fehlt: ans Ende des Objekts.
    if Close < 0 then
      raise EArgumentException.Create('atlas.json: Objekt nicht geschlossen');
    if Count > 0 then
    begin
      // Letztes Glied suchen (kein Schlüssel heißt #0): Einrückung und Einfügestelle.
      Scanner.Find(Open, #0, Probe, Dummy, Close, Count);
      Indent := Scanner.LineIndent(Dummy.KeyStart);
      Insert := Nested(Parts, Index, AJson, Indent, Step, LB);
      // Steht schon ein Komma dahinter (erlaubtes Schlusskomma), dahinter einfügen.
      Pos := Dummy.ValueStop;
      Scanner.SkipSpace(Pos);
      if (Pos <= Length(Result)) and (Result[Pos] = ',') then
        Exit(Copy(Result, 1, Pos) + LB + Indent + Insert + Copy(Result, Pos + 1, MaxInt));
      Exit(Copy(Result, 1, Dummy.ValueStop - 1) + ',' + LB + Indent + Insert + Copy(Result, Dummy.ValueStop, MaxInt));
    end;
    Indent := Scanner.LineIndent(Open);
    Insert := Nested(Parts, Index, AJson, Indent + Step, Step, LB);
    Exit(Copy(Result, 1, Open) + LB + Indent + Step + Insert + LB + Indent + Copy(Result, Close, MaxInt));
  end;
end;

class function TAtlasJsonText.ApplyChanges(const AText: string;
  const AChanges: TArray<TPair<string, string>>): string;
var
  Change: TPair<string, string>;
begin
  Result := AText;
  for Change in AChanges do
    if Change.Value = '' then
      Result := Remove(Result, Change.Key)
    else
      Result := SetValue(Result, Change.Key, Change.Value);
end;

class function TAtlasJsonText.Remove(const AText, APath: string): string;
var
  Scanner: TScanner;
  Parts: TArray<string>;
  Open, Close, Count, Index, Pos, Comma, LineStart: Integer;
  Member, Previous: TMember;
begin
  Result := AText;
  Scanner.Text := AText;
  Parts := Segments(APath);
  Open := 1;
  Scanner.SkipSpace(Open);
  if (Open > Length(AText)) or (AText[Open] <> '{') then
    Exit;
  for Index := 0 to High(Parts) do
  begin
    if not Scanner.Find(Open, Parts[Index], Member, Previous, Close, Count) then
      Exit;
    if Index < High(Parts) then
    begin
      if AText[Member.ValueStart] <> '{' then
        Exit;
      Open := Member.ValueStart;
      Continue;
    end;
    // Mit Vorgänger: dessen Komma und die Zeile des Schlüssels entfernen; Kommentare dazwischen bleiben.
    if Previous.KeyStart > 0 then
    begin
      Comma := Previous.ValueStop;
      Scanner.SkipSpace(Comma);
      LineStart := Member.KeyStart;
      while (LineStart > 1) and CharInSet(AText[LineStart - 1], [' ', #9]) do
        Dec(LineStart);
      if (LineStart > 1) and (AText[LineStart - 1] = #10) then
        Dec(LineStart);
      if (LineStart > 1) and (AText[LineStart - 1] = #13) then
        Dec(LineStart);
      if (Comma > Length(AText)) or (AText[Comma] <> ',') or (LineStart <= Comma) then
        Exit(Copy(AText, 1, Previous.ValueStop - 1) + Copy(AText, Member.ValueStop, MaxInt));
      Exit(Copy(AText, 1, Comma - 1) + Copy(AText, Comma + 1, LineStart - Comma - 1) +
        Copy(AText, Member.ValueStop, MaxInt));
    end;
    // Erstes Glied: bis zum nächsten Schlüssel bzw. bis vor die schließende Klammer.
    Pos := Member.ValueStop;
    Scanner.SkipSpace(Pos);
    if (Pos <= Length(AText)) and (AText[Pos] = ',') then
    begin
      Inc(Pos);
      Scanner.SkipSpace(Pos);
      Exit(Copy(AText, 1, Member.KeyStart - 1) + Copy(AText, Pos, MaxInt));
    end;
    // Einziges Glied: Objekt leeren.
    Exit(Copy(AText, 1, Open) + Copy(AText, Close, MaxInt));
  end;
end;

end.
