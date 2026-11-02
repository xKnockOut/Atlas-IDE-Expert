unit Atlas.Core.Editor.SmartPaste;

// Einfügen mit uses-Ergänzung (#515), Plugin-Kern ohne VCL und Open Tools API:
// - Einstellung editor.smartPaste: off, uses, indent, both.
// - Erkennen: Ein Einfügen zählt ab einem Zeilenumbruch oder 20 Zeichen. Nach
//   einer Änderung im Editor steht der eingefügte Text direkt vor dem Cursor
//   (Match), gleich ob über Strg+V, Umschalt+Einfg oder das Kontextmenü.
// - Einrückung (Reindent): Die erste Zeile des Blocks kommt auf die
//   Einrückung der Einfügestelle, die übrigen behalten ihren Abstand dazu.
//   Ziel ist der Leerraum vor der Einfügestelle; steht der Cursor am
//   Zeilenanfang, die Einrückung der Zeile darüber, eine Stufe mehr nach
//   einem öffnenden Wort (begin, try, then, do …). Beginnt die erste Zeile
//   ohne Leerraum (aus der Mitte einer Zeile kopiert), gilt als ihre
//   Einrückung die kleinste der übrigen Zeilen, eine Stufe weniger nach einem
//   öffnenden Wort. Steht vor der Einfügestelle Code oder ist es nur eine
//   Zeile, bleibt alles, wie es ist. Tabulatoren zählen bis zur nächsten
//   Tabulatorposition; neue Einrückung besteht aus Leerzeichen.
// - Antwort des Servers (atlas.server.pasteUses) lesen: eindeutige Units und
//   mehrdeutige Bezeichner mit Auswahl; die gewählten Units zusammenstellen.

interface

uses
  System.SysUtils,
  System.JSON;

type
{$SCOPEDENUMS ON}
  TAtlasPasteMode = (Off, UsesOnly, IndentOnly, Both);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Zeile der Einrückung: in Zeile Line (relativ zur ersten Zeile des Blocks) die ersten Remove
  /// Zeichen durch Indent ersetzen.</summary>
  TAtlasIndentEdit = record
    Line: Integer;
    Remove: Integer;
    Indent: string;
  end;

  /// <summary>Mehrdeutiger Bezeichner: Units zur Wahl, Chosen = Index oder -1 (keine).</summary>
  TAtlasPasteChoice = record
    Name: string;
    Units: TArray<string>;
    Chosen: Integer;
  end;

  TAtlasPasteAnalysis = record
    Valid: Boolean;
    Units: TArray<string>;
    Choices: TArray<TAtlasPasteChoice>;
    InInterface: Boolean;
  end;

  TAtlasSmartPaste = class
  public const
    Command = 'atlas.server.pasteUses';
    ModeOff = 'off';
    ModeUses = 'uses';
    ModeIndent = 'indent';
    ModeBoth = 'both';
    /// <summary>Kürzere Einfügungen ohne Zeilenumbruch übergeht Atlas.</summary>
    MinChars = 20;
    /// <summary>So viele Unit-Namen nennt die Überschrift, dann „…“.</summary>
    MaxNamed = 3;
  public
    class function ModeOf(const AValue: string): TAtlasPasteMode; static;
    class function WantsUses(AMode: TAtlasPasteMode): Boolean; static;
    class function WantsIndent(AMode: TAtlasPasteMode): Boolean; static;
    /// <summary>Zählt das als Einfügen eines Blocks (Zeilenumbruch oder ab MinChars Zeichen)?</summary>
    class function Qualifies(const AText: string): Boolean; static;
    /// <summary>Stehen die Zeilen APasted direkt vor dem Cursor? ALines: die letzten Length(APasted) Zeilen des
    /// Puffers bis zur Cursorzeile; ACaret: Zeichenindex (0-basiert) in der letzten. AStart: Zeichenindex des
    /// Anfangs in ALines[0].</summary>
    class function Match(const ALines: TArray<string>; ACaret: Integer; const APasted: TArray<string>;
      out AStart: Integer): Boolean; static;
    /// <summary>Breite des führenden Leerraums (Tabulatoren bis zur nächsten Position).</summary>
    class function IndentWidth(const ALine: string; ATabWidth: Integer): Integer; static;
    /// <summary>Endet die Zeile (ohne Kommentar) mit einem Wort, nach dem eingerückt wird?</summary>
    class function Opens(const ALine: string): Boolean; static;
    /// <summary>Einrückung für den eingefügten Block APasted; APrefix: Zeile vor der Einfügestelle, AAbove: die
    /// nächste nicht leere Zeile darüber ('' ohne). False ohne Änderung.</summary>
    class function Reindent(const APrefix, AAbove: string; const APasted: TArray<string>; ATabWidth, AStep: Integer;
      out AEdits: TArray<TAtlasIndentEdit>): Boolean; static;
    /// <summary>Antwort des Servers ohne gewählte Units; Valid = False ohne gültige Antwort.</summary>
    class function ReadAnalysis(AValue: TJSONValue): TAtlasPasteAnalysis; static;
    /// <summary>Eindeutige und gewählte Units ohne Doppelte.</summary>
    class function Selected(const AAnalysis: TAtlasPasteAnalysis): TArray<string>; static;
    /// <summary>Namen für die Überschrift: höchstens MaxNamed, dann „…“.</summary>
    class function Named(const AUnits: TArray<string>): string; static;
    /// <summary>JSON-Argumente [uri, range] bzw. [uri, range, [Units]] (Zeilen und Zeichen 0-basiert).</summary>
    class function Arguments(const AUri: string; AStartLine, AStartCharacter, AEndLine, AEndCharacter: Integer):
      string; overload; static;
    class function Arguments(const AUri: string; AStartLine, AStartCharacter, AEndLine, AEndCharacter: Integer;
      const AUnits: TArray<string>): string; overload; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections;

const
  Openers: array[0..15] of string = ('begin', 'try', 'finally', 'except', 'repeat', 'then', 'do', 'else', 'of',
    'record', 'class', 'var', 'const', 'type', 'private', 'public');
  /// <summary>Wörter, mit denen eine Zeile auf der Ebene des öffnenden Worts steht.</summary>
  Closers: array[0..4] of string = ('end', 'else', 'until', 'except', 'finally');

function Contains(const ANames: TArray<string>; const AName: string): Boolean;
var
  Name: string;
begin
  for Name in ANames do
  begin
    if SameText(Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function LeadLength(const ALine: string): Integer;
begin
  Result := 0;
  while (Result < Length(ALine)) and ((ALine[Result + 1] = ' ') or (ALine[Result + 1] = #9)) do
  begin
    Inc(Result);
  end;
end;

function Quoted(const AText: string): string;
var
  Value: TJSONString;
begin
  Value := TJSONString.Create(AText);
  try
    Result := Value.ToJSON;
  finally
    Value.Free;
  end;
end;

function IsBlank(const ALine: string): Boolean;
begin
  Result := Trim(ALine) = '';
end;

function Closes(const ALine: string): Boolean;
var
  Text: string;
  Stop: Integer;
begin
  Text := TrimLeft(ALine);
  Stop := 0;
  while (Stop < Length(Text)) and CharInSet(Text[Stop + 1], ['A'..'Z', 'a'..'z']) do
  begin
    Inc(Stop);
  end;
  Result := MatchText(Copy(Text, 1, Stop), Closers);
end;

{ TAtlasSmartPaste }

class function TAtlasSmartPaste.ModeOf(const AValue: string): TAtlasPasteMode;
begin
  if SameText(AValue, ModeBoth) then
  begin
    Result := TAtlasPasteMode.Both;
  end
  else if SameText(AValue, ModeUses) then
  begin
    Result := TAtlasPasteMode.UsesOnly;
  end
  else if SameText(AValue, ModeIndent) then
  begin
    Result := TAtlasPasteMode.IndentOnly;
  end
  else
  begin
    Result := TAtlasPasteMode.Off;
  end;
end;

class function TAtlasSmartPaste.WantsUses(AMode: TAtlasPasteMode): Boolean;
begin
  Result := (AMode = TAtlasPasteMode.UsesOnly) or (AMode = TAtlasPasteMode.Both);
end;

class function TAtlasSmartPaste.WantsIndent(AMode: TAtlasPasteMode): Boolean;
begin
  Result := (AMode = TAtlasPasteMode.IndentOnly) or (AMode = TAtlasPasteMode.Both);
end;

class function TAtlasSmartPaste.Qualifies(const AText: string): Boolean;
begin
  Result := (Pos(#10, AText) > 0) or (Pos(#13, AText) > 0) or (Length(AText) >= MinChars);
end;

class function TAtlasSmartPaste.Match(const ALines: TArray<string>; ACaret: Integer; const APasted: TArray<string>;
  out AStart: Integer): Boolean;
var
  Count, Index: Integer;
  Last: string;
begin
  AStart := -1;
  Result := False;
  Count := Length(APasted);
  if (Count = 0) or (Length(ALines) <> Count) or (ACaret < 0) or (ACaret > Length(ALines[Count - 1])) then
  begin
    Exit;
  end;
  Last := Copy(ALines[Count - 1], 1, ACaret);
  if not Last.EndsWith(APasted[Count - 1]) then
  begin
    Exit;
  end;
  if Count = 1 then
  begin
    AStart := ACaret - Length(APasted[0]);
    Exit(True);
  end;
  for Index := 1 to Count - 2 do
  begin
    if ALines[Index] <> APasted[Index] then
    begin
      Exit;
    end;
  end;
  if not ALines[0].EndsWith(APasted[0]) then
  begin
    Exit;
  end;
  AStart := Length(ALines[0]) - Length(APasted[0]);
  Result := True;
end;

class function TAtlasSmartPaste.IndentWidth(const ALine: string; ATabWidth: Integer): Integer;
var
  Index: Integer;
begin
  Result := 0;
  if ATabWidth < 1 then
  begin
    ATabWidth := 1;
  end;
  for Index := 1 to LeadLength(ALine) do
  begin
    if ALine[Index] = #9 then
    begin
      Result := (Result div ATabWidth + 1) * ATabWidth;
    end
    else
    begin
      Inc(Result);
    end;
  end;
end;

class function TAtlasSmartPaste.Opens(const ALine: string): Boolean;
var
  Text, Word: string;
  Cut, Start: Integer;
begin
  Text := ALine;
  Cut := Pos('//', Text);
  if Cut > 0 then
  begin
    Text := Copy(Text, 1, Cut - 1);
  end;
  Text := TrimRight(Text);
  Start := Length(Text);
  while (Start > 0) and CharInSet(Text[Start], ['A'..'Z', 'a'..'z', '_']) do
  begin
    Dec(Start);
  end;
  Word := Copy(Text, Start + 1, MaxInt);
  // „class“ nur als Typdeklaration (= class), nicht in „class function“.
  Result := (Word <> '') and MatchText(Word, Openers) and ((Start = 0) or (Text[Start] <> '.'));
end;

class function TAtlasSmartPaste.Reindent(const APrefix, AAbove: string; const APasted: TArray<string>;
  ATabWidth, AStep: Integer; out AEdits: TArray<TAtlasIndentEdit>): Boolean;
var
  First, Index, Target, Base, Smallest, Closing, Delta, Width: Integer;
  Edit: TAtlasIndentEdit;
begin
  AEdits := nil;
  Result := False;
  if (Length(APasted) < 2) or not IsBlank(APrefix) then
  begin
    Exit;
  end;
  // Erste Zeile mit Inhalt.
  First := -1;
  for Index := 0 to High(APasted) do
  begin
    if not IsBlank(APasted[Index]) then
    begin
      First := Index;
      Break;
    end;
  end;
  if First < 0 then
  begin
    Exit;
  end;
  if APrefix <> '' then
  begin
    Target := IndentWidth(APrefix, ATabWidth);
  end
  else
  begin
    Target := IndentWidth(AAbove, ATabWidth);
    if Opens(AAbove) then
    begin
      Inc(Target, AStep);
    end;
  end;
  Base := IndentWidth(APasted[First], ATabWidth);
  if (First = 0) and (LeadLength(APasted[0]) = 0) then
  begin
    // Eine Zeile mit end, else … steht auf der Ebene der ersten; sonst die flachste, nach einem öffnenden Wort
    // eine Stufe darüber.
    Smallest := -1;
    Closing := -1;
    for Index := 1 to High(APasted) do
    begin
      if not IsBlank(APasted[Index]) then
      begin
        Width := IndentWidth(APasted[Index], ATabWidth);
        if (Smallest < 0) or (Width < Smallest) then
        begin
          Smallest := Width;
        end;
        if Closes(APasted[Index]) and ((Closing < 0) or (Width < Closing)) then
        begin
          Closing := Width;
        end;
      end;
    end;
    if Closing >= 0 then
    begin
      Base := Closing;
    end
    else if Smallest > 0 then
    begin
      Base := Smallest;
      if Opens(APasted[0]) then
      begin
        Base := Base - AStep;
      end;
      if Base < 0 then
      begin
        Base := 0;
      end;
    end;
  end;
  Delta := Target - Base;
  for Index := First to High(APasted) do
  begin
    if IsBlank(APasted[Index]) then
    begin
      Continue;
    end;
    Edit.Line := Index;
    if Index = 0 then
    begin
      // In der ersten Zeile steht der Leerraum vor der Einfügestelle mit davor.
      Edit.Remove := Length(APrefix) + LeadLength(APasted[0]);
      Edit.Indent := StringOfChar(' ', Target);
      if Edit.Indent = APrefix + Copy(APasted[0], 1, LeadLength(APasted[0])) then
      begin
        Continue;
      end;
    end
    else
    begin
      Width := IndentWidth(APasted[Index], ATabWidth) + Delta;
      if Width < 0 then
      begin
        Width := 0;
      end;
      Edit.Remove := LeadLength(APasted[Index]);
      Edit.Indent := StringOfChar(' ', Width);
      if Edit.Indent = Copy(APasted[Index], 1, Edit.Remove) then
      begin
        Continue;
      end;
    end;
    AEdits := AEdits + [Edit];
  end;
  Result := AEdits <> nil;
end;

class function TAtlasSmartPaste.ReadAnalysis(AValue: TJSONValue): TAtlasPasteAnalysis;
var
  Reply, Item: TJSONObject;
  Value, UnitValue: TJSONValue;
  Choice: TAtlasPasteChoice;
begin
  Result := Default(TAtlasPasteAnalysis);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  Reply := TJSONObject(AValue);
  if not (Reply.GetValue('units') is TJSONArray) or not (Reply.GetValue('choices') is TJSONArray) then
  begin
    Exit;
  end;
  Result.Valid := True;
  for Value in TJSONArray(Reply.GetValue('units')) do
  begin
    if Value is TJSONString then
    begin
      Result.Units := Result.Units + [Value.Value];
    end;
  end;
  for Value in TJSONArray(Reply.GetValue('choices')) do
  begin
    if not (Value is TJSONObject) then
    begin
      Continue;
    end;
    Item := TJSONObject(Value);
    Choice := Default(TAtlasPasteChoice);
    Choice.Chosen := -1;
    if Item.GetValue('name') is TJSONString then
    begin
      Choice.Name := Item.GetValue('name').Value;
    end;
    if Item.GetValue('units') is TJSONArray then
    begin
      for UnitValue in TJSONArray(Item.GetValue('units')) do
      begin
        if UnitValue is TJSONString then
        begin
          Choice.Units := Choice.Units + [UnitValue.Value];
        end;
      end;
    end;
    if Length(Choice.Units) > 1 then
    begin
      Result.Choices := Result.Choices + [Choice];
    end;
  end;
  Result.InInterface := (Reply.GetValue('interface') is TJSONBool) and TJSONBool(Reply.GetValue('interface')).AsBoolean;
end;

class function TAtlasSmartPaste.Selected(const AAnalysis: TAtlasPasteAnalysis): TArray<string>;
var
  Name: string;
  Choice: TAtlasPasteChoice;
begin
  Result := nil;
  for Name in AAnalysis.Units do
  begin
    if not Contains(Result, Name) then
    begin
      Result := Result + [Name];
    end;
  end;
  for Choice in AAnalysis.Choices do
  begin
    if (Choice.Chosen >= 0) and (Choice.Chosen <= High(Choice.Units)) and
      not Contains(Result, Choice.Units[Choice.Chosen]) then
    begin
      Result := Result + [Choice.Units[Choice.Chosen]];
    end;
  end;
end;

class function TAtlasSmartPaste.Named(const AUnits: TArray<string>): string;
begin
  if Length(AUnits) <= MaxNamed then
  begin
    Result := string.Join(', ', AUnits);
  end
  else
  begin
    Result := string.Join(', ', Copy(AUnits, 0, MaxNamed)) + ', …';
  end;
end;

class function TAtlasSmartPaste.Arguments(const AUri: string; AStartLine, AStartCharacter, AEndLine,
  AEndCharacter: Integer): string;
begin
  Result := Format('[%s,{"start":{"line":%d,"character":%d},"end":{"line":%d,"character":%d}}]',
    [Quoted(AUri), AStartLine, AStartCharacter, AEndLine, AEndCharacter]);
end;

class function TAtlasSmartPaste.Arguments(const AUri: string; AStartLine, AStartCharacter, AEndLine,
  AEndCharacter: Integer; const AUnits: TArray<string>): string;
var
  List: TJSONArray;
  Name: string;
begin
  List := TJSONArray.Create;
  try
    for Name in AUnits do
    begin
      List.Add(Name);
    end;
    Result := Arguments(AUri, AStartLine, AStartCharacter, AEndLine, AEndCharacter);
    // Die Liste kommt vor die schließende Klammer.
    Result := Copy(Result, 1, Length(Result) - 1) + ',' + List.ToJSON + ']';
  finally
    List.Free;
  end;
end;

end.
