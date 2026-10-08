unit BDLsp.Common.Editing.Modernizer;

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
    class function WordPos(const AWord, ALine: string; AFrom: Integer = 1): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

function IsIdentChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function IndentOf(const ALine: string): Integer;
begin
  Result := Length(ALine) - Length(TrimLeft(ALine));
end;

class function TModernizer.WordPos(const AWord, ALine: string; AFrom: Integer): Integer;
var
  Index: Integer;
  InString: Boolean;
begin
  InString := False;
  Index := 1;
  while Index <= Length(ALine) - Length(AWord) + 1 do
  begin
    if ALine[Index] = '''' then
      InString := not InString
    else if not InString and (Index >= AFrom) and SameText(Copy(ALine, Index, Length(AWord)), AWord) and
      ((Index = 1) or not IsIdentChar(ALine[Index - 1])) and
      ((Index + Length(AWord) > Length(ALine)) or not IsIdentChar(ALine[Index + Length(AWord)])) then
      Exit(Index)
    else if not InString and (Copy(ALine, Index, 2) = '//') then
      Exit(0);
    Inc(Index);
  end;
  Result := 0;
end;

function Occurs(const AWord: string; const ALines: TArray<string>; AFirst, ALast: Integer): Boolean;
var
  Line: Integer;
begin
  for Line := AFirst to ALast do
    if TModernizer.WordPos(AWord, ALines[Line]) > 0 then
      Exit(True);
  Result := False;
end;

procedure Delete(var ALines: TArray<string>; AIndex: Integer);
var
  Line: Integer;
begin
  for Line := AIndex to High(ALines) - 1 do
    ALines[Line] := ALines[Line + 1];
  SetLength(ALines, Length(ALines) - 1);
end;

/// <summary>Zeile des "begin" der Routine (Einrückung wie der Kopf); -1 ohne.</summary>
function MainBegin(const ALines: TArray<string>): Integer;
var
  Line: Integer;
begin
  for Line := 1 to High(ALines) do
    if SameText(Trim(ALines[Line]), 'begin') and (IndentOf(ALines[Line]) = IndentOf(ALines[0])) then
      Exit(Line);
  Result := -1;
end;

/// <summary>X.Free; X := nil; wird zu FreeAndNil(X);</summary>
function ApplyFreeAndNil(var ALines: TArray<string>): Integer;
var
  Line: Integer;
  Text, Name: string;
begin
  Result := 0;
  Line := 0;
  while Line < High(ALines) do
  begin
    Text := Trim(ALines[Line]);
    if EndsText('.Free;', Text) then
    begin
      Name := Copy(Text, 1, Length(Text) - 6);
      if (Name <> '') and SameText(Trim(ALines[Line + 1]), Name + ' := nil;') then
      begin
        ALines[Line] := Copy(ALines[Line], 1, IndentOf(ALines[Line])) + 'FreeAndNil(' + Name + ');';
        Delete(ALines, Line + 1);
        Inc(Result);
      end;
    end;
    Inc(Line);
  end;
end;

/// <summary>Liste L aus der Obergrenze "L.Count - 1", "High(L)" oder "Length(L) - 1"; '' sonst.</summary>
function ListOf(const AUpper: string): string;
var
  Text: string;
begin
  Text := Trim(AUpper);
  Result := '';
  if EndsText('.Count - 1', Text) then
    Result := Copy(Text, 1, Length(Text) - 10)
  else if StartsText('High(', Text) and EndsStr(')', Text) then
    Result := Copy(Text, 6, Length(Text) - 6)
  else if StartsText('Length(', Text) and EndsText(') - 1', Text) then
    Result := Copy(Text, 8, Length(Text) - 11);
  Result := Trim(Result);
  if (Result = '') or (Pos('(', Result) > 0) or (Pos(' ', Result) > 0) then
    Result := '';
end;

/// <summary>Letzte Zeile des Schleifenrumpfs ab AFirst; -1, wenn er nicht sicher erkennbar ist.</summary>
function BodyEnd(const ALines: TArray<string>; AFirst, AHeaderIndent: Integer): Integer;
var
  Line: Integer;
begin
  if AFirst > High(ALines) then
    Exit(-1);
  if SameText(Trim(ALines[AFirst]), 'begin') then
  begin
    for Line := AFirst + 1 to High(ALines) do
      if (IndentOf(ALines[Line]) <= IndentOf(ALines[AFirst])) and (Trim(ALines[Line]) <> '') then
      begin
        if StartsText('end', Trim(ALines[Line])) and (IndentOf(ALines[Line]) = IndentOf(ALines[AFirst])) then
          Exit(Line);
        Exit(-1);
      end;
    Exit(-1);
  end;
  // Einzelne Anweisung in einer Zeile.
  if (IndentOf(ALines[AFirst]) > AHeaderIndent) and EndsStr(';', TrimRight(ALines[AFirst])) then
    Exit(AFirst);
  Result := -1;
end;

/// <summary>Ersetzt L[I] in ALine durch AItem; False, wenn I anders vorkommt oder L[I] beschrieben wird.</summary>
function ReplaceAccess(var ALine: string; const AList, AIndex, AItem: string): Boolean;
var
  Access, Rest: string;
  At, Word: Integer;
begin
  Access := AList + '[' + AIndex + ']';
  Rest := ALine;
  ALine := '';
  repeat
    At := Pos(LowerCase(Access), LowerCase(Rest));
    if (At > 1) and (IsIdentChar(Rest[At - 1]) or (Rest[At - 1] = '.')) then
      At := 0;
    if At = 0 then
      Break;
    if StartsStr(':=', TrimLeft(Copy(Rest, At + Length(Access), MaxInt))) then
      Exit(False);
    ALine := ALine + Copy(Rest, 1, At - 1) + AItem;
    Rest := Copy(Rest, At + Length(Access), MaxInt);
  until False;
  ALine := ALine + Rest;
  Word := TModernizer.WordPos(AIndex, ALine);
  Result := Word = 0;
end;

const
  Mutators: array[0..9] of string = ('Add', 'Delete', 'Insert', 'Remove', 'Clear', 'Exchange', 'Move', 'Extract',
    'Sort', 'AddRange');

function ApplyForIn(var ALines: TArray<string>; var AFreed: TArray<string>): Integer;
var
  Line, Last, Body, Indent: Integer;
  Text, Index, Upper, List, Item, Changed: string;
  Assign, ToPos: Integer;
  Replaced: TArray<string>;
  Ok: Boolean;
  Mutator: string;
begin
  Result := 0;
  for Line := 0 to High(ALines) do
  begin
    Text := Trim(ALines[Line]);
    if not StartsText('for ', Text) or not EndsText(' do', Text) then
      Continue;
    Assign := Pos(' := ', Text);
    ToPos := Pos(' to ', LowerCase(Text));
    if (Assign = 0) or (ToPos < Assign) or (Trim(Copy(Text, Assign + 4, ToPos - Assign - 4)) <> '0') then
      Continue;
    Index := Trim(Copy(Text, 5, Assign - 5));
    if not IsValidIdent(Index) then
      Continue;
    Upper := Copy(Text, ToPos + 4, Length(Text) - ToPos - 6);
    List := ListOf(Upper);
    if List = '' then
      Continue;
    Indent := IndentOf(ALines[Line]);
    Last := BodyEnd(ALines, Line + 1, Indent);
    if Last < 0 then
      Continue;
    Item := 'Item';
    if Occurs(Item, ALines, 0, High(ALines)) then
      Item := 'Element';
    if Occurs(Item, ALines, 0, High(ALines)) then
      Continue;
    Ok := True;
    SetLength(Replaced, Last - Line);
    for Body := Line + 1 to Last do
    begin
      Changed := ALines[Body];
      if not ReplaceAccess(Changed, List, Index, Item) then
        Ok := False;
      for Mutator in Mutators do
        if Pos(LowerCase(List + '.' + Mutator + '('), LowerCase(Changed)) > 0 then
          Ok := False;
      Replaced[Body - Line - 1] := Changed;
    end;
    // Ohne Zugriff L[I] im Rumpf bringt for-in nichts.
    if not Ok or not Occurs(Item, Replaced, 0, High(Replaced)) then
      Continue;
    ALines[Line] := Copy(ALines[Line], 1, Indent) + Format('for var %s in %s do', [Item, List]);
    for Body := Line + 1 to Last do
      ALines[Body] := Replaced[Body - Line - 1];
    AFreed := AFreed + [Index];
    Inc(Result);
  end;
end;

/// <summary>Deklaration "Name: Typ;" (ein Name, kein Vorgabewert) zerlegen.</summary>
function SingleDeclaration(const ALine: string; out AName, AType: string): Boolean;
var
  Text: string;
  Colon: Integer;
begin
  Text := Trim(ALine);
  Colon := Pos(':', Text);
  Result := (Colon > 1) and EndsStr(';', Text) and (Pos('=', Text) = 0) and (Pos(',', Text) = 0) and
    (Pos('//', Text) = 0) and (Pos('{', Text) = 0);
  if not Result then
    Exit;
  AName := Trim(Copy(Text, 1, Colon - 1));
  AType := Trim(Copy(Text, Colon + 1, Length(Text) - Colon - 1));
  Result := IsValidIdent(AName) and (AType <> '');
end;

/// <summary>Inline-Variablen; Zählvariablen aus AFreed, die nicht mehr vorkommen, fallen weg.</summary>
function ApplyInlineVar(var ALines: TArray<string>; AInline: Boolean; const AFreed: TArray<string>): Integer;
var
  Line, Start, Stop, BeginLine, Use, Declaration: Integer;
  Name, TypeName, Text: string;
  Done: Boolean;
begin
  Result := 0;
  repeat
    Done := True;
    BeginLine := MainBegin(ALines);
    if BeginLine < 0 then
      Exit;
    Line := 1;
    while Line < BeginLine do
    begin
      if not SameText(Trim(ALines[Line]), 'var') then
      begin
        Inc(Line);
        Continue;
      end;
      Start := Line + 1;
      Stop := Start;
      while (Stop < BeginLine) and (IndentOf(ALines[Stop]) > IndentOf(ALines[Line])) do
        Inc(Stop);
      for Declaration := Start to Stop - 1 do
      begin
        if not SingleDeclaration(ALines[Declaration], Name, TypeName) then
          Continue;
        // Nicht in verschachtelten Routinen oder weiteren Deklarationen verwendet.
        if Occurs(Name, ALines, Stop, BeginLine) then
          Continue;
        Use := BeginLine + 1;
        while (Use <= High(ALines)) and (TModernizer.WordPos(Name, ALines[Use]) = 0) do
          Inc(Use);
        if Use > High(ALines) then
        begin
          // Zählvariable einer umgewandelten Schleife, die nicht mehr gebraucht wird.
          if (IndexText(Name, AFreed) < 0) or Occurs(Name, ALines, 0, Line - 1) then
            Continue;
          Delete(ALines, Declaration);
          if Start = Stop - 1 then
            Delete(ALines, Line);
          Done := False;
          Break;
        end;
        if not AInline then
          Continue;
        Text := Trim(ALines[Use]);
        if (IndentOf(ALines[Use]) <> IndentOf(ALines[BeginLine]) + 2) or not StartsText(Name + ' := ', Text) or
          not EndsStr(';', Text) or (TModernizer.WordPos(Name, Text, Length(Name) + 1) > 0) then
          Continue;
        ALines[Use] := Copy(ALines[Use], 1, IndentOf(ALines[Use])) + Format('var %s: %s := %s', [Name, TypeName,
          Copy(Text, Length(Name) + 5, MaxInt)]);
        Delete(ALines, Declaration);
        // Leerer var-Abschnitt fällt weg.
        if Start = Stop - 1 then
          Delete(ALines, Line);
        Inc(Result);
        Done := False;
        Break;
      end;
      if not Done then
        Break;
      Line := Stop;
    end;
  until Done;
end;

class function TModernizer.Apply(const ALines: TArray<string>; AKinds: TModernizations;
  out ACount: Integer): TArray<string>;
var
  Freed: TArray<string>;
begin
  Freed := nil;
  Result := Copy(ALines);
  ACount := 0;
  if TModernization.FreeAndNilCall in AKinds then
    ACount := ACount + ApplyFreeAndNil(Result);
  if TModernization.ForIn in AKinds then
    ACount := ACount + ApplyForIn(Result, Freed);
  if (TModernization.InlineVar in AKinds) or (Freed <> nil) then
    ACount := ACount + ApplyInlineVar(Result, TModernization.InlineVar in AKinds, Freed);
end;

end.
