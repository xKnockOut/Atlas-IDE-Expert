unit Atlas.Common.Editing.Modernizer;

// Modernisierungen für eine Routine (#303, /modern; Teilmenge von #71). Arbeitet
// zeilenweise auf dem Text der Routine (Kopf bis "end;") und lässt alles
// unverändert, was es nicht sicher erkennt:
//   ForIn       for I := 0 to L.Count - 1 do … L[I] … wird zu for var Item in L do … Item …,
//               nur wenn I ausschließlich als L[I] gelesen und L im Rumpf nicht verändert wird
//   InlineVar   Deklaration im var-Abschnitt und erste Zuweisung auf oberster Ebene des
//               Rumpfs werden zu var X: T := Wert;
//   FreeAndNil  X.Free; gefolgt von X := nil; wird zu FreeAndNil(X);
// ForIn und InlineVar brauchen Inline-Variablen (ab Delphi 10.3).

interface

type
  TModernization = (ForIn, InlineVar, FreeAndNilCall);
  TModernizations = set of TModernization;

  TModernizer = class
  public
    /// <summary>Wendet AKinds auf die Zeilen einer Routine an; ACount zählt die Umformungen.</summary>
    class function Apply(const ALines: TArray<string>; AKinds: TModernizations;
      out ACount: Integer): TArray<string>; static;
    /// <summary>Position von AWord als ganzes Wort in ALine ab AFrom (außerhalb von Strings); 0 ohne.</summary>
    class function WordPos(const AWord, ALine: string; AFrom: Integer): Integer; overload; static;
    /// <summary>Wie oben mit AFrom = 1.</summary>
    class function WordPos(const AWord, ALine: string): Integer; overload; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Chars,
  Atlas.Text.Lines;

class function TModernizer.WordPos(const AWord, ALine: string): Integer;
begin
  Result := WordPos(AWord, ALine, 1);
end;

/// <summary>Beginnt an AIndex ein Wort (davor kein Bezeichnerzeichen)?</summary>
function StartsWord(const ALine: string; AIndex: Integer): Boolean;
begin
  Result := (AIndex = 1) or not TTextChars.IsAsciiIdentChar(ALine[AIndex - 1]);
end;

/// <summary>Endet vor AAfter ein Wort (dort kein Bezeichnerzeichen)?</summary>
function EndsWord(const ALine: string; AAfter: Integer): Boolean;
begin
  Result := (AAfter > Length(ALine)) or not TTextChars.IsAsciiIdentChar(ALine[AAfter]);
end;

/// <summary>Steht AWord an AIndex als ganzes Wort?</summary>
function IsWordAt(const AWord, ALine: string; AIndex: Integer): Boolean;
begin
  Result := SameText(Copy(ALine, AIndex, Length(AWord)), AWord) and StartsWord(ALine, AIndex) and
    EndsWord(ALine, AIndex + Length(AWord));
end;

class function TModernizer.WordPos(const AWord, ALine: string; AFrom: Integer): Integer;
var
  mIndex: Integer;
  mInString: Boolean;
begin
  mInString := False;
  mIndex := 1;
  while mIndex <= Length(ALine) - Length(AWord) + 1 do
  begin
    if ALine[mIndex] = '''' then
    begin
      mInString := not mInString;
    end
    else if not mInString and (mIndex >= AFrom) and IsWordAt(AWord, ALine, mIndex) then
    begin
      Exit(mIndex);
    end
    else if not mInString and (Copy(ALine, mIndex, 2) = '//') then
    begin
      Exit(0);
    end;
    Inc(mIndex);
  end;
  Result := 0;
end;

function Occurs(const AWord: string; const ALines: TArray<string>; AFirst, ALast: Integer): Boolean;
var
  mLine: Integer;
begin
  for mLine := AFirst to ALast do
  begin
    if TModernizer.WordPos(AWord, ALines[mLine]) > 0 then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure Delete(var ALines: TArray<string>; AIndex: Integer);
var
  mLine: Integer;
begin
  for mLine := AIndex to High(ALines) - 1 do
  begin
    ALines[mLine] := ALines[mLine + 1];
  end;
  SetLength(ALines, Length(ALines) - 1);
end;

/// <summary>Zeile des "begin" der Routine (Einrückung wie der Kopf); -1 ohne.</summary>
function MainBegin(const ALines: TArray<string>): Integer;
var
  mLine: Integer;
begin
  for mLine := 1 to High(ALines) do
  begin
    if SameText(Trim(ALines[mLine]), 'begin') and
      (TTextLines.IndentLength(ALines[mLine]) = TTextLines.IndentLength(ALines[0])) then
    begin
      Exit(mLine);
    end;
  end;
  Result := -1;
end;

/// <summary>X.Free; X := nil; wird zu FreeAndNil(X);</summary>
function ApplyFreeAndNil(var ALines: TArray<string>): Integer;
var
  mLine: Integer;
  mText, mName: string;
begin
  Result := 0;
  mLine := 0;
  while mLine < High(ALines) do
  begin
    mText := Trim(ALines[mLine]);
    if EndsText('.Free;', mText) then
    begin
      mName := Copy(mText, 1, Length(mText) - 6);
      if (mName <> '') and SameText(Trim(ALines[mLine + 1]), mName + ' := nil;') then
      begin
        ALines[mLine] := Copy(ALines[mLine], 1, TTextLines.IndentLength(ALines[mLine])) + 'FreeAndNil(' + mName + ');';
        Delete(ALines, mLine + 1);
        Inc(Result);
      end;
    end;
    Inc(mLine);
  end;
end;

/// <summary>Liste L aus der Obergrenze "L.Count - 1", "High(L)" oder "Length(L) - 1"; '' sonst.</summary>
function ListOf(const AUpper: string): string;
var
  mText: string;
begin
  mText := Trim(AUpper);
  Result := '';
  if EndsText('.Count - 1', mText) then
  begin
    Result := Copy(mText, 1, Length(mText) - 10);
  end
  else if StartsText('High(', mText) and EndsStr(')', mText) then
  begin
    Result := Copy(mText, 6, Length(mText) - 6);
  end
  else if StartsText('Length(', mText) and EndsText(') - 1', mText) then
  begin
    Result := Copy(mText, 8, Length(mText) - 11);
  end;
  Result := Trim(Result);
  if (Result = '') or (Pos('(', Result) > 0) or (Pos(' ', Result) > 0) then
  begin
    Result := '';
  end;
end;

/// <summary>Zeile des end zum begin in Zeile AFirst; -1, wenn es nicht sicher erkennbar ist.</summary>
function BlockEnd(const ALines: TArray<string>; AFirst: Integer): Integer;
var
  mLine, mIndent: Integer;
begin
  mIndent := TTextLines.IndentLength(ALines[AFirst]);
  for mLine := AFirst + 1 to High(ALines) do
  begin
    if (TTextLines.IndentLength(ALines[mLine]) <= mIndent) and (Trim(ALines[mLine]) <> '') then
    begin
      if StartsText('end', Trim(ALines[mLine])) and (TTextLines.IndentLength(ALines[mLine]) = mIndent) then
      begin
        Exit(mLine);
      end;
      Exit(-1);
    end;
  end;
  Result := -1;
end;

/// <summary>Letzte Zeile des Schleifenrumpfs ab AFirst; -1, wenn er nicht sicher erkennbar ist.</summary>
function BodyEnd(const ALines: TArray<string>; AFirst, AHeaderIndent: Integer): Integer;
begin
  if AFirst > High(ALines) then
  begin
    Result := -1;
  end
  else if SameText(Trim(ALines[AFirst]), 'begin') then
  begin
    Result := BlockEnd(ALines, AFirst);
  end
  // Einzelne Anweisung in einer Zeile.
  else if (TTextLines.IndentLength(ALines[AFirst]) > AHeaderIndent) and EndsStr(';', TrimRight(ALines[AFirst])) then
  begin
    Result := AFirst;
  end
  else
  begin
    Result := -1;
  end;
end;

/// <summary>Ersetzt L[I] in ALine durch AItem; False, wenn I anders vorkommt oder L[I] beschrieben wird.</summary>
function ReplaceAccess(var ALine: string; const AList, AIndex, AItem: string): Boolean;
var
  mAccess, mRest: string;
  mAt, mWord: Integer;
begin
  mAccess := AList + '[' + AIndex + ']';
  mRest := ALine;
  ALine := '';
  repeat
    mAt := Pos(LowerCase(mAccess), LowerCase(mRest));
    if (mAt > 1) and (TTextChars.IsAsciiIdentChar(mRest[mAt - 1]) or (mRest[mAt - 1] = '.')) then
    begin
      mAt := 0;
    end;
    if mAt = 0 then
    begin
      Break;
    end;
    if StartsStr(':=', TrimLeft(Copy(mRest, mAt + Length(mAccess), MaxInt))) then
    begin
      Exit(False);
    end;
    ALine := ALine + Copy(mRest, 1, mAt - 1) + AItem;
    mRest := Copy(mRest, mAt + Length(mAccess), MaxInt);
  until False;
  ALine := ALine + mRest;
  mWord := TModernizer.WordPos(AIndex, ALine);
  Result := mWord = 0;
end;

const
  cMutators: array[0..9] of string = ('Add', 'Delete', 'Insert', 'Remove', 'Clear', 'Exchange', 'Move', 'Extract',
    'Sort', 'AddRange');

/// <summary>Zerlegt "for I := 0 to L.Count - 1 do" in Zählvariable und Liste; False bei anderer Form.</summary>
function ParseFor(const AText: string; out AIndex, AList: string): Boolean;
var
  mAssign, mTo: Integer;
begin
  AIndex := '';
  AList := '';
  if not StartsText('for ', AText) or not EndsText(' do', AText) then
  begin
    Exit(False);
  end;
  mAssign := Pos(' := ', AText);
  mTo := Pos(' to ', LowerCase(AText));
  if (mAssign = 0) or (mTo < mAssign) or (Trim(Copy(AText, mAssign + 4, mTo - mAssign - 4)) <> '0') then
  begin
    Exit(False);
  end;
  AIndex := Trim(Copy(AText, 5, mAssign - 5));
  AList := ListOf(Copy(AText, mTo + 4, Length(AText) - mTo - 6));
  Result := IsValidIdent(AIndex) and (AList <> '');
end;

/// <summary>Name für das Element: Item, sonst Element; False, wenn beide schon vorkommen.</summary>
function FreeItemName(const ALines: TArray<string>; out AItem: string): Boolean;
begin
  AItem := 'Item';
  if Occurs(AItem, ALines, 0, High(ALines)) then
  begin
    AItem := 'Element';
  end;
  Result := not Occurs(AItem, ALines, 0, High(ALines));
end;

/// <summary>Ruft ALine eine Methode auf, die die Liste AList verändert?</summary>
function Mutates(const AList, ALine: string): Boolean;
var
  mMutator: string;
begin
  for mMutator in cMutators do
  begin
    if Pos(LowerCase(AList + '.' + mMutator + '('), LowerCase(ALine)) > 0 then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Rumpf mit AItem statt AList[AIndex]; False, wenn AIndex anders vorkommt oder AList verändert wird.
/// </summary>
function ReplacedBody(const ABody: TArray<string>; const AList, AIndex, AItem: string;
  out AReplaced: TArray<string>): Boolean;
var
  mLine: Integer;
  mChanged: string;
begin
  Result := True;
  SetLength(AReplaced, Length(ABody));
  for mLine := 0 to High(ABody) do
  begin
    mChanged := ABody[mLine];
    if not ReplaceAccess(mChanged, AList, AIndex, AItem) or Mutates(AList, mChanged) then
    begin
      Result := False;
    end;
    AReplaced[mLine] := mChanged;
  end;
end;

/// <summary>Wandelt die Zählschleife in Zeile ALine in for-in um; AIndex ist dann ihre frei gewordene
/// Zählvariable.</summary>
function ConvertLoop(var ALines: TArray<string>; ALine: Integer; out AIndex: string): Boolean;
var
  mList, mItem: string;
  mIndent, mLast, mBody: Integer;
  mReplaced: TArray<string>;
begin
  Result := False;
  if not ParseFor(Trim(ALines[ALine]), AIndex, mList) then
  begin
    Exit;
  end;
  mIndent := TTextLines.IndentLength(ALines[ALine]);
  mLast := BodyEnd(ALines, ALine + 1, mIndent);
  if (mLast < 0) or not FreeItemName(ALines, mItem) then
  begin
    Exit;
  end;
  // Ohne Zugriff L[I] im Rumpf bringt for-in nichts.
  if not ReplacedBody(Copy(ALines, ALine + 1, mLast - ALine), mList, AIndex, mItem, mReplaced) or
    not Occurs(mItem, mReplaced, 0, High(mReplaced)) then
  begin
    Exit;
  end;
  ALines[ALine] := Copy(ALines[ALine], 1, mIndent) + Format('for var %s in %s do', [mItem, mList]);
  for mBody := ALine + 1 to mLast do
  begin
    ALines[mBody] := mReplaced[mBody - ALine - 1];
  end;
  Result := True;
end;

function ApplyForIn(var ALines: TArray<string>; var AFreed: TArray<string>): Integer;
var
  mLine: Integer;
  mIndex: string;
begin
  Result := 0;
  for mLine := 0 to High(ALines) do
  begin
    if ConvertLoop(ALines, mLine, mIndex) then
    begin
      AFreed := AFreed + [mIndex];
      Inc(Result);
    end;
  end;
end;

/// <summary>Deklaration "Name: Typ;" (ein Name, kein Vorgabewert) zerlegen.</summary>
function SingleDeclaration(const ALine: string; out AName, AType: string): Boolean;
var
  mText: string;
  mColon: Integer;
begin
  mText := Trim(ALine);
  mColon := Pos(':', mText);
  Result := (mColon > 1) and EndsStr(';', mText) and (Pos('=', mText) = 0) and (Pos(',', mText) = 0) and
    (Pos('//', mText) = 0) and (Pos('{', mText) = 0);
  if not Result then
  begin
    Exit;
  end;
  AName := Trim(Copy(mText, 1, mColon - 1));
  AType := Trim(Copy(mText, mColon + 1, Length(mText) - mColon - 1));
  Result := IsValidIdent(AName) and (AType <> '');
end;

type
  /// <summary>Ein var-Abschnitt vor dem Rumpf: Zeile von var, erste Zeile dahinter und Zeile von begin.</summary>
  TVarSection = record
    VarLine: Integer;
    Stop: Integer;
    BeginLine: Integer;
  end;

/// <summary>Erste Zeile hinter dem var-Abschnitt in Zeile AVarLine (weniger eingerückt).</summary>
function SectionStop(const ALines: TArray<string>; AVarLine, ABeginLine: Integer): Integer;
var
  mIndent: Integer;
begin
  mIndent := TTextLines.IndentLength(ALines[AVarLine]);
  Result := AVarLine + 1;
  while (Result < ABeginLine) and (TTextLines.IndentLength(ALines[Result]) > mIndent) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Erste Zeile ab AFrom, in der AName vorkommt; hinter der letzten, wenn keine.</summary>
function FirstUse(const ALines: TArray<string>; const AName: string; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result <= High(ALines)) and (TModernizer.WordPos(AName, ALines[Result]) = 0) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Zählvariable einer umgewandelten Schleife, die nicht mehr gebraucht wird (auch nicht vor dem
/// var-Abschnitt in Zeile AVarLine)?</summary>
function IsFreedCounter(const ALines: TArray<string>; const AName: string; const AFreed: TArray<string>;
  AVarLine: Integer): Boolean;
begin
  Result := (IndexText(AName, AFreed) >= 0) and not Occurs(AName, ALines, 0, AVarLine - 1);
end;

/// <summary>Entfernt die Deklaration in Zeile ADeclaration; ein leerer var-Abschnitt fällt mit weg.</summary>
procedure RemoveDeclaration(var ALines: TArray<string>; const ASection: TVarSection; ADeclaration: Integer);
begin
  Delete(ALines, ADeclaration);
  if ASection.VarLine + 1 = ASection.Stop - 1 then
  begin
    Delete(ALines, ASection.VarLine);
  end;
end;

/// <summary>Macht die erste Zuweisung "Name := Wert;" in Zeile AUse auf oberster Ebene des Rumpfs (begin in
/// ABeginLine) zu "var Name: Typ := Wert;"; False bei anderer Form.</summary>
function InlineAt(var ALines: TArray<string>; AUse, ABeginLine: Integer; const AName, ATypeName: string): Boolean;
var
  mText: string;
begin
  mText := Trim(ALines[AUse]);
  Result := (TTextLines.IndentLength(ALines[AUse]) = TTextLines.IndentLength(ALines[ABeginLine]) + 2) and
    StartsText(AName + ' := ', mText) and EndsStr(';', mText) and
    (TModernizer.WordPos(AName, mText, Length(AName) + 1) = 0);
  if Result then
  begin
    ALines[AUse] := Copy(ALines[AUse], 1, TTextLines.IndentLength(ALines[AUse])) +
      Format('var %s: %s := %s', [AName, ATypeName, Copy(mText, Length(AName) + 5, MaxInt)]);
  end;
end;

/// <summary>Eine Änderung im var-Abschnitt ASection: eine unbenutzte Zählvariable aus AFreed entfernen oder (mit
/// AInline) eine Deklaration zur Inline-Variablen machen (ACounted); False ohne.</summary>
function ChangeInSection(var ALines: TArray<string>; const ASection: TVarSection; AInline: Boolean;
  const AFreed: TArray<string>; out ACounted: Boolean): Boolean;
var
  mDeclaration, mUse: Integer;
  mName, mTypeName: string;
  mUnused: Boolean;
begin
  ACounted := False;
  for mDeclaration := ASection.VarLine + 1 to ASection.Stop - 1 do
  begin
    // Nicht in verschachtelten Routinen oder weiteren Deklarationen verwendet.
    if not SingleDeclaration(ALines[mDeclaration], mName, mTypeName) or
      Occurs(mName, ALines, ASection.Stop, ASection.BeginLine) then
    begin
      Continue;
    end;
    mUse := FirstUse(ALines, mName, ASection.BeginLine + 1);
    mUnused := mUse > High(ALines);
    ACounted := not mUnused and AInline and InlineAt(ALines, mUse, ASection.BeginLine, mName, mTypeName);
    if ACounted or (mUnused and IsFreedCounter(ALines, mName, AFreed, ASection.VarLine)) then
    begin
      RemoveDeclaration(ALines, ASection, mDeclaration);
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Eine Änderung in den var-Abschnitten vor dem Rumpf; False, wenn keine mehr geht.</summary>
function NextInlineChange(var ALines: TArray<string>; AInline: Boolean; const AFreed: TArray<string>;
  out ACounted: Boolean): Boolean;
var
  mSection: TVarSection;
  mLine: Integer;
begin
  ACounted := False;
  mSection.BeginLine := MainBegin(ALines);
  mLine := 1;
  while mLine < mSection.BeginLine do
  begin
    if not SameText(Trim(ALines[mLine]), 'var') then
    begin
      Inc(mLine);
      Continue;
    end;
    mSection.VarLine := mLine;
    mSection.Stop := SectionStop(ALines, mLine, mSection.BeginLine);
    if ChangeInSection(ALines, mSection, AInline, AFreed, ACounted) then
    begin
      Exit(True);
    end;
    mLine := mSection.Stop;
  end;
  Result := False;
end;

/// <summary>Inline-Variablen; Zählvariablen aus AFreed, die nicht mehr vorkommen, fallen weg.</summary>
function ApplyInlineVar(var ALines: TArray<string>; AInline: Boolean; const AFreed: TArray<string>): Integer;
var
  mCounted: Boolean;
begin
  Result := 0;
  while NextInlineChange(ALines, AInline, AFreed, mCounted) do
  begin
    if mCounted then
    begin
      Inc(Result);
    end;
  end;
end;

class function TModernizer.Apply(const ALines: TArray<string>; AKinds: TModernizations;
  out ACount: Integer): TArray<string>;
var
  mFreed: TArray<string>;
begin
  mFreed := nil;
  Result := Copy(ALines);
  ACount := 0;
  if TModernization.FreeAndNilCall in AKinds then
  begin
    ACount := ACount + ApplyFreeAndNil(Result);
  end;
  if TModernization.ForIn in AKinds then
  begin
    ACount := ACount + ApplyForIn(Result, mFreed);
  end;
  if (TModernization.InlineVar in AKinds) or (mFreed <> nil) then
  begin
    ACount := ACount + ApplyInlineVar(Result, TModernization.InlineVar in AKinds, mFreed);
  end;
end;

end.
