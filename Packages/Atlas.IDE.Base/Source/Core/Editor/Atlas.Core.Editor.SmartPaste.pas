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
//   Tabulatorposition; neue Einrückung besteht aus Leerzeichen. Kennt der
//   Server die Spalte nach der Blockstruktur (#1832, wie nach Enter), gilt
//   sie für die erste Zeile statt der Heuristik.
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
    /// <summary>Reindent ohne Spalte vom Server: die Heuristik bestimmt sie.</summary>
    NoColumn = -1;
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
    /// nächste nicht leere Zeile darüber ('' ohne); AColumn: Spalte vom Server nach der Blockstruktur (#1832),
    /// NoColumn für die Heuristik. False ohne Änderung.</summary>
    class function Reindent(const APrefix, AAbove: string; const APasted: TArray<string>; ATabWidth, AStep,
      AColumn: Integer; out AEdits: TArray<TAtlasIndentEdit>): Boolean; static;
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
  cOpeners: array[0..15] of string = ('begin', 'try', 'finally', 'except', 'repeat', 'then', 'do', 'else', 'of',
    'record', 'class', 'var', 'const', 'type', 'private', 'public');
  /// <summary>Wörter, mit denen eine Zeile auf der Ebene des öffnenden Worts steht.</summary>
  cClosers: array[0..4] of string = ('end', 'else', 'until', 'except', 'finally');

function Contains(const ANames: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  for mName in ANames do
  begin
    if SameText(mName, AName) then
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
  mValue: TJSONString;
begin
  mValue := TJSONString.Create(AText);
  try
    Result := mValue.ToJSON;
  finally
    mValue.Free;
  end;
end;

function IsBlank(const ALine: string): Boolean;
begin
  Result := Trim(ALine) = '';
end;

function Closes(const ALine: string): Boolean;
var
  mText: string;
  mStop: Integer;
begin
  mText := TrimLeft(ALine);
  mStop := 0;
  while (mStop < Length(mText)) and CharInSet(mText[mStop + 1], ['A'..'Z', 'a'..'z']) do
  begin
    Inc(mStop);
  end;
  Result := MatchText(Copy(mText, 1, mStop), cClosers);
end;

/// <summary>Stimmen die Zeilen zwischen der ersten und der letzten überein?</summary>
function MiddleLinesEqual(const ALines, APasted: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := True;
  for mIndex := 1 to Length(APasted) - 2 do
  begin
    Result := Result and (ALines[mIndex] = APasted[mIndex]);
  end;
end;

/// <summary>Erste Zeile mit Inhalt; -1 ohne.</summary>
function FirstContent(const APasted: TArray<string>): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  mIndex := 0;
  while (Result < 0) and (mIndex <= High(APasted)) do
  begin
    if not IsBlank(APasted[mIndex]) then
    begin
      Result := mIndex;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Kleinste Einrückung der Zeilen ab der zweiten und die kleinste einer Zeile mit end, else …; -1 ohne.
/// </summary>
procedure ScanWidths(const APasted: TArray<string>; ATabWidth: Integer; out ASmallest, AClosing: Integer);
var
  mIndex, mWidth: Integer;
begin
  ASmallest := -1;
  AClosing := -1;
  for mIndex := 1 to High(APasted) do
  begin
    if not IsBlank(APasted[mIndex]) then
    begin
      mWidth := TAtlasSmartPaste.IndentWidth(APasted[mIndex], ATabWidth);
      if (ASmallest < 0) or (mWidth < ASmallest) then
      begin
        ASmallest := mWidth;
      end;
      if Closes(APasted[mIndex]) and ((AClosing < 0) or (mWidth < AClosing)) then
      begin
        AClosing := mWidth;
      end;
    end;
  end;
end;

/// <summary>Ziel: Leerraum vor der Einfügestelle, am Zeilenanfang die Einrückung der Zeile darüber (eine Stufe
/// mehr nach einem öffnenden Wort).</summary>
function TargetIndent(const APrefix, AAbove: string; ATabWidth, AStep: Integer): Integer;
begin
  if APrefix <> '' then
  begin
    Result := TAtlasSmartPaste.IndentWidth(APrefix, ATabWidth);
  end
  else
  begin
    Result := TAtlasSmartPaste.IndentWidth(AAbove, ATabWidth);
    if TAtlasSmartPaste.Opens(AAbove) then
    begin
      Inc(Result, AStep);
    end;
  end;
end;

/// <summary>Einrückung des Blocks: die der ersten Zeile mit Inhalt; ohne Leerraum am Anfang (aus der Mitte einer
/// Zeile kopiert) die einer Zeile mit end, else …, sonst die flachste, nach einem öffnenden Wort eine Stufe
/// darüber.</summary>
function BaseIndent(const APasted: TArray<string>; AFirst, ATabWidth, AStep: Integer): Integer;
var
  mSmallest, mClosing: Integer;
begin
  Result := TAtlasSmartPaste.IndentWidth(APasted[AFirst], ATabWidth);
  if (AFirst = 0) and (LeadLength(APasted[0]) = 0) then
  begin
    ScanWidths(APasted, ATabWidth, mSmallest, mClosing);
    if mClosing >= 0 then
    begin
      Result := mClosing;
    end
    else if mSmallest > 0 then
    begin
      Result := mSmallest;
      if TAtlasSmartPaste.Opens(APasted[0]) then
      begin
        Result := Result - AStep;
      end;
      if Result < 0 then
      begin
        Result := 0;
      end;
    end;
  end;
end;

/// <summary>Erste Zeile: Der Leerraum vor der Einfügestelle steht mit davor. False ohne Änderung.</summary>
function FirstLineEdit(const APrefix, ALine: string; ATarget: Integer; out AEdit: TAtlasIndentEdit): Boolean;
begin
  AEdit.Line := 0;
  AEdit.Remove := Length(APrefix) + LeadLength(ALine);
  AEdit.Indent := StringOfChar(' ', ATarget);
  Result := AEdit.Indent <> APrefix + Copy(ALine, 1, LeadLength(ALine));
end;

/// <summary>Weitere Zeile AIndex: Einrückung um ADelta verschoben (nicht unter 0). False ohne Änderung.</summary>
function OtherLineEdit(const ALine: string; AIndex, ADelta, ATabWidth: Integer; out AEdit: TAtlasIndentEdit):
  Boolean;
var
  mWidth: Integer;
begin
  mWidth := TAtlasSmartPaste.IndentWidth(ALine, ATabWidth) + ADelta;
  if mWidth < 0 then
  begin
    mWidth := 0;
  end;
  AEdit.Line := AIndex;
  AEdit.Remove := LeadLength(ALine);
  AEdit.Indent := StringOfChar(' ', mWidth);
  Result := AEdit.Indent <> Copy(ALine, 1, AEdit.Remove);
end;

/// <summary>Zeichenketten in AValue, wenn es ein Array ist.</summary>
function StringsOf(AValue: TJSONValue): TArray<string>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mItem in TJSONArray(AValue) do
    begin
      if mItem is TJSONString then
      begin
        Result := Result + [mItem.Value];
      end;
    end;
  end;
end;

function ReadChoice(AItem: TJSONObject): TAtlasPasteChoice;
begin
  Result := Default(TAtlasPasteChoice);
  Result.Chosen := -1;
  if AItem.GetValue('name') is TJSONString then
  begin
    Result.Name := AItem.GetValue('name').Value;
  end;
  Result.Units := StringsOf(AItem.GetValue('units'));
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
  mCount: Integer;
begin
  AStart := -1;
  mCount := Length(APasted);
  Result := (mCount > 0) and (Length(ALines) = mCount) and (ACaret >= 0) and (ACaret <= Length(ALines[mCount - 1]));
  Result := Result and Copy(ALines[mCount - 1], 1, ACaret).EndsWith(APasted[mCount - 1]);
  if Result and (mCount = 1) then
  begin
    AStart := ACaret - Length(APasted[0]);
  end
  else if Result then
  begin
    Result := MiddleLinesEqual(ALines, APasted) and ALines[0].EndsWith(APasted[0]);
    if Result then
    begin
      AStart := Length(ALines[0]) - Length(APasted[0]);
    end;
  end;
end;

class function TAtlasSmartPaste.IndentWidth(const ALine: string; ATabWidth: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  if ATabWidth < 1 then
  begin
    ATabWidth := 1;
  end;
  for mIndex := 1 to LeadLength(ALine) do
  begin
    if ALine[mIndex] = #9 then
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
  mText, mWord: string;
  mCut, mStart: Integer;
begin
  mText := ALine;
  mCut := Pos('//', mText);
  if mCut > 0 then
  begin
    mText := Copy(mText, 1, mCut - 1);
  end;
  mText := TrimRight(mText);
  mStart := Length(mText);
  while (mStart > 0) and CharInSet(mText[mStart], ['A'..'Z', 'a'..'z', '_']) do
  begin
    Dec(mStart);
  end;
  mWord := Copy(mText, mStart + 1, MaxInt);
  // „class“ nur als Typdeklaration (= class), nicht in „class function“.
  Result := (mWord <> '') and MatchText(mWord, cOpeners) and ((mStart = 0) or (mText[mStart] <> '.'));
end;

class function TAtlasSmartPaste.Reindent(const APrefix, AAbove: string; const APasted: TArray<string>;
  ATabWidth, AStep, AColumn: Integer; out AEdits: TArray<TAtlasIndentEdit>): Boolean;
var
  mFirst, mIndex, mTarget, mDelta: Integer;
  mEdit: TAtlasIndentEdit;
  mChanged: Boolean;
begin
  AEdits := nil;
  mFirst := -1;
  if (Length(APasted) >= 2) and IsBlank(APrefix) then
  begin
    mFirst := FirstContent(APasted);
  end;
  if mFirst >= 0 then
  begin
    mTarget := AColumn;
    if mTarget = NoColumn then
    begin
      mTarget := TargetIndent(APrefix, AAbove, ATabWidth, AStep);
    end;
    mDelta := mTarget - BaseIndent(APasted, mFirst, ATabWidth, AStep);
    for mIndex := mFirst to High(APasted) do
    begin
      if IsBlank(APasted[mIndex]) then
      begin
        mChanged := False;
      end
      else if mIndex = 0 then
      begin
        mChanged := FirstLineEdit(APrefix, APasted[0], mTarget, mEdit);
      end
      else
      begin
        mChanged := OtherLineEdit(APasted[mIndex], mIndex, mDelta, ATabWidth, mEdit);
      end;
      if mChanged then
      begin
        AEdits := AEdits + [mEdit];
      end;
    end;
  end;
  Result := AEdits <> nil;
end;

class function TAtlasSmartPaste.ReadAnalysis(AValue: TJSONValue): TAtlasPasteAnalysis;
var
  mReply: TJSONObject;
  mValue: TJSONValue;
  mChoice: TAtlasPasteChoice;
begin
  Result := Default(TAtlasPasteAnalysis);
  mReply := nil;
  if AValue is TJSONObject then
  begin
    mReply := TJSONObject(AValue);
    Result.Valid := (mReply.GetValue('units') is TJSONArray) and (mReply.GetValue('choices') is TJSONArray);
  end;
  if Result.Valid then
  begin
    Result.Units := StringsOf(mReply.GetValue('units'));
    for mValue in TJSONArray(mReply.GetValue('choices')) do
    begin
      if mValue is TJSONObject then
      begin
        mChoice := ReadChoice(TJSONObject(mValue));
        if Length(mChoice.Units) > 1 then
        begin
          Result.Choices := Result.Choices + [mChoice];
        end;
      end;
    end;
    Result.InInterface := (mReply.GetValue('interface') is TJSONBool) and
      TJSONBool(mReply.GetValue('interface')).AsBoolean;
  end;
end;

class function TAtlasSmartPaste.Selected(const AAnalysis: TAtlasPasteAnalysis): TArray<string>;
var
  mName: string;
  mChoice: TAtlasPasteChoice;
begin
  Result := nil;
  for mName in AAnalysis.Units do
  begin
    if not Contains(Result, mName) then
    begin
      Result := Result + [mName];
    end;
  end;
  for mChoice in AAnalysis.Choices do
  begin
    if (mChoice.Chosen >= 0) and (mChoice.Chosen <= High(mChoice.Units)) and
      not Contains(Result, mChoice.Units[mChoice.Chosen]) then
    begin
      Result := Result + [mChoice.Units[mChoice.Chosen]];
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
  mList: TJSONArray;
  mName: string;
begin
  mList := TJSONArray.Create;
  try
    for mName in AUnits do
    begin
      mList.Add(mName);
    end;
    Result := Arguments(AUri, AStartLine, AStartCharacter, AEndLine, AEndCharacter);
    // Die Liste kommt vor die schließende Klammer.
    Result := Copy(Result, 1, Length(Result) - 1) + ',' + mList.ToJSON + ']';
  finally
    mList.Free;
  end;
end;

end.
