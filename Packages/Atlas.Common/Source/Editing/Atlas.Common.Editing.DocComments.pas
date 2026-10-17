unit Atlas.Common.Editing.DocComments;

// Gerüst für Dokumentationskommentare (#88). Nach dem dritten "/" in einer
// sonst leeren Zeile direkt über einer Deklaration entsteht
//   /// <summary></summary>
//   /// <typeparam name="T"></typeparam>   je generischem Parameter
//   /// <param name="A"></param>           je Parameter, in Reihenfolge
//   /// <returns></returns>                nur bei Funktionen und Operatoren
// Properties, Typen, Felder und Konstanten erhalten nur <summary>. Dazu zwei
// Code-Aktionen: Kommentar erzeugen und <param> an die Signatur anpassen.
// Beim Anpassen fehlen keine Beschreibungen: Ein <param> ohne Parameter in der
// Signatur wird zu <!-- entfernt: Name: Beschreibung --> und nicht gelöscht.
// Abschaltbar mit "completeBlocks.docComment" (Aufrufer prüft die Einstellung).

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.CodeActions;

type
  TDocSignature = record
    IsRoutine: Boolean;
    HasResult: Boolean;
    TypeParams: TArray<string>;
    Params: TArray<string>;
  end;

  TDocComments = class
  public
    /// <summary>Signatur der Deklaration, die in Zeile ALine beginnt.</summary>
    class function Signature(const ALines: TArray<string>; ALine: Integer): TDocSignature; static;
    /// <summary>Kommentarzeilen zur Signatur, jede mit AIndent davor.</summary>
    class function Skeleton(const ASignature: TDocSignature; const AIndent: string): TArray<string>; static;
    /// <summary>Gerüst nach dem dritten "/" an APosition; False, wenn die Zeile nicht passt.</summary>
    class function AfterSlash(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      out AEdit: TTextEdit): Boolean; static;
    /// <summary>Code-Aktionen zur Deklaration in Zeile ALine: Kommentar erzeugen, &lt;param&gt; anpassen.</summary>
    class function Actions(const AText: string; ATree: TSyntaxTree; ALine: Integer): TArray<TCodeAction>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Lines;

const
  DeclarationKinds = [TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl, TSyntaxKind.Field,
    TSyntaxKind.PropertyDecl, TSyntaxKind.RoutineHeader, TSyntaxKind.RoutineDecl];
  RoutineWords: array[0..4] of string = ('function', 'procedure', 'constructor', 'destructor', 'operator');

/// <summary>Teile von AText an ASeparator auf Klammertiefe 0.</summary>
function SplitTop(const AText: string; ASeparator: Char): TArray<string>;
var
  Index, Depth, Start: Integer;
begin
  Result := nil;
  Depth := 0;
  Start := 1;
  for Index := 1 to Length(AText) do
    case AText[Index] of
      '(', '[', '<':
        Inc(Depth);
      ')', ']', '>':
        Dec(Depth);
    else
      if (AText[Index] = ASeparator) and (Depth = 0) then
      begin
        Result := Result + [Copy(AText, Start, Index - Start)];
        Start := Index + 1;
      end;
    end;
  Result := Result + [Copy(AText, Start, MaxInt)];
end;

/// <summary>Deklarationstext ab ALine bis zum ";" auf Klammertiefe 0.</summary>
function DeclarationText(const ALines: TArray<string>; ALine: Integer): string;
var
  Line, Index, Depth: Integer;
  Text: string;
begin
  Result := '';
  Depth := 0;
  for Line := ALine to High(ALines) do
  begin
    Text := ALines[Line];
    if Pos('//', Text) > 0 then
      Text := Copy(Text, 1, Pos('//', Text) - 1);
    for Index := 1 to Length(Text) do
    begin
      case Text[Index] of
        '(':
          Inc(Depth);
        ')':
          Dec(Depth);
        ';':
          if Depth = 0 then
            Exit(Result + Copy(Text, 1, Index));
      end;
    end;
    Result := Result + Text + ' ';
  end;
end;

/// <summary>Namen aus einer Parametergruppe "const [Ref] A, B: Integer = 0".</summary>
function GroupNames(const AGroup: string): TArray<string>;
var
  Text, Name: string;
  Colon, Bracket: Integer;
begin
  Result := nil;
  Text := Trim(AGroup);
  Colon := Pos(':', Text);
  if Colon > 0 then
    Text := Copy(Text, 1, Colon - 1);
  // Attribute wie [Ref] entfernen.
  Bracket := Pos(']', Text);
  if (Pos('[', Text) > 0) and (Bracket > 0) then
    Text := Copy(Text, 1, Pos('[', Text) - 1) + Copy(Text, Bracket + 1, MaxInt);
  Text := Trim(Text);
  for Name in ['const ', 'var ', 'out ', 'constref '] do
    if StartsText(Name, Text) then
      Text := Trim(Copy(Text, Length(Name) + 1, MaxInt));
  for Name in SplitTop(Text, ',') do
    if IsValidIdent(Trim(Name)) then
      Result := Result + [Trim(Name)];
end;

class function TDocComments.Signature(const ALines: TArray<string>; ALine: Integer): TDocSignature;
var
  Text, Word, Head, Generic, Part: string;
  Open, Close, Depth, Index, Less: Integer;
begin
  Result := Default(TDocSignature);
  Text := Trim(DeclarationText(ALines, ALine));
  if StartsText('class ', Text) then
    Text := Trim(Copy(Text, 7, MaxInt));
  Word := LowerCase(Copy(Text, 1, Pos(' ', Text + ' ') - 1));
  if IndexText(Word, RoutineWords) < 0 then
    Exit;
  Result.IsRoutine := True;
  Result.HasResult := MatchText(Word, ['function', 'operator']);
  Text := Trim(Copy(Text, Length(Word) + 1, MaxInt));
  Open := Pos('(', Text);
  if Open = 0 then
    Head := Copy(Text, 1, Pos(';', Text + ';') - 1)
  else
    Head := Copy(Text, 1, Open - 1);
  if Pos(':', Head) > 0 then
    Head := Copy(Head, 1, Pos(':', Head) - 1);
  // Generische Parameter am Namen (nicht am Klassennamen davor).
  Less := LastDelimiter('<', Head);
  if (Less > 0) and (Less > LastDelimiter('.', Head)) then
  begin
    Generic := Copy(Head, Less + 1, LastDelimiter('>', Head) - Less - 1);
    for Part in SplitTop(StringReplace(Generic, ';', ',', [rfReplaceAll]), ',') do
      if IsValidIdent(Trim(Copy(Part, 1, Pos(':', Part + ':') - 1))) then
        Result.TypeParams := Result.TypeParams + [Trim(Copy(Part, 1, Pos(':', Part + ':') - 1))];
  end;
  if Open = 0 then
    Exit;
  Depth := 0;
  Close := 0;
  for Index := Open to Length(Text) do
  begin
    if Text[Index] = '(' then
      Inc(Depth)
    else if Text[Index] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Close := Index;
        Break;
      end;
    end;
  end;
  if Close = 0 then
    Exit;
  for Part in SplitTop(Copy(Text, Open + 1, Close - Open - 1), ';') do
    Result.Params := Result.Params + GroupNames(Part);
end;

class function TDocComments.Skeleton(const ASignature: TDocSignature; const AIndent: string): TArray<string>;
var
  Name: string;
begin
  Result := [AIndent + '/// <summary></summary>'];
  for Name in ASignature.TypeParams do
    Result := Result + [AIndent + Format('/// <typeparam name="%s"></typeparam>', [Name])];
  for Name in ASignature.Params do
    Result := Result + [AIndent + Format('/// <param name="%s"></param>', [Name])];
  if ASignature.HasResult then
    Result := Result + [AIndent + '/// <returns></returns>'];
end;

function FindDeclaration(ANode: TSyntaxNode; ALine: Integer): Boolean;
var
  Index: Integer;
begin
  if (ANode.Kind in DeclarationKinds) and (ANode.StartPos.Line = ALine) then
    Exit(True);
  for Index := 0 to ANode.ChildCount - 1 do
    if (ANode[Index].StartPos.Line <= ALine) and (ANode[Index].EndPos.Line >= ALine) and
      FindDeclaration(ANode[Index], ALine) then
      Exit(True);
  Result := False;
end;

/// <summary>Beginnt in Zeile ALine eine Deklaration (Typ, Konstante, Variable, Feld, Property, Routine)?</summary>
function IsDeclarationLine(ATree: TSyntaxTree; const ALines: TArray<string>; ALine: Integer): Boolean;
begin
  Result := (ATree <> nil) and (ATree.Root <> nil) and (ALine >= 0) and (ALine <= High(ALines)) and
    (Trim(ALines[ALine]) <> '') and FindDeclaration(ATree.Root, ALine);
end;

function IsDocLine(const ALine: string): Boolean;
begin
  Result := StartsStr('///', TrimLeft(ALine));
end;

class function TDocComments.AfterSlash(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  out AEdit: TTextEdit): Boolean;
var
  Lines: TArray<string>;
  Line: Integer;
  Skeleton: TArray<string>;
begin
  Result := False;
  Lines := TTextLines.SplitLines(AText);
  Line := APosition.Line;
  if (Line < 0) or (Line >= High(Lines)) or (Trim(Lines[Line]) <> '///') then
    Exit;
  // Schon dokumentiert oder kein Ziel darunter.
  if ((Line > 0) and IsDocLine(Lines[Line - 1])) or not IsDeclarationLine(ATree, Lines, Line + 1) then
    Exit;
  Skeleton := TDocComments.Skeleton(TDocComments.Signature(Lines, Line + 1), TTextLines.IndentOf(Lines[Line]));
  AEdit := TTextEdit.Create(TTextRange.Create(Line, 0, Line, Length(Lines[Line])),
    TTextLines.JoinLines(Skeleton, TTextLines.LineBreakOf(AText)));
  Result := True;
end;

/// <summary>Name aus einer Zeile "/// &lt;param name="X"&gt;"; '' sonst.</summary>
function ParamName(const ALine: string): string;
var
  Start, Stop: Integer;
begin
  Result := '';
  Start := Pos('<param name="', ALine);
  if Start = 0 then
    Exit;
  Start := Start + Length('<param name="');
  Stop := PosEx('"', ALine, Start);
  if Stop > Start then
    Result := Copy(ALine, Start, Stop - Start);
end;

/// <summary>Bearbeitungen, die den &lt;param&gt; ab Zeile ALine als &lt;!-- entfernt: Name --&gt; markieren;
/// die Beschreibung bleibt im Kommentar. ALast = letzte Kommentarzeile, bis zu der &lt;/param&gt; gesucht wird.</summary>
function MarkRemoved(const ALines: TArray<string>; ALine, ALast: Integer; const AName: string): TArray<TTextEdit>;
const
  CloseTag = '</param>';
var
  Open, OpenEnd, Close, Line: Integer;
  Description: string;
begin
  Open := Pos('<param name="', ALines[ALine]);
  OpenEnd := PosEx('>', ALines[ALine], Open);
  Close := PosEx(CloseTag, ALines[ALine], OpenEnd);
  if Close > 0 then
  begin
    // "--" ist in einem XML-Kommentar nicht erlaubt.
    Description := Trim(StringReplace(Copy(ALines[ALine], OpenEnd + 1, Close - OpenEnd - 1), '--', '–',
      [rfReplaceAll]));
    if Description <> '' then
      Description := ': ' + Description;
    Result := [TTextEdit.Create(TTextRange.Create(ALine, Open - 1, ALine, Close - 1 + Length(CloseTag)),
      Format('<!-- entfernt: %s%s -->', [AName, Description]))];
    Exit;
  end;
  // Mehrzeilig: Anfang und Ende des Tags ersetzen, die Zeilen dazwischen bleiben.
  Result := [TTextEdit.Create(TTextRange.Create(ALine, Open - 1, ALine, OpenEnd),
    Format('<!-- entfernt: %s:', [AName]))];
  for Line := ALine + 1 to ALast do
  begin
    Close := Pos(CloseTag, ALines[Line]);
    if Close > 0 then
    begin
      Result := Result + [TTextEdit.Create(TTextRange.Create(Line, Close - 1, Line, Close - 1 + Length(CloseTag)),
        '-->')];
      Exit;
    end;
  end;
  // Kein Ende gefunden: nur den Anfang markieren und schließen.
  Result := [TTextEdit.Create(TTextRange.Create(ALine, Open - 1, ALine, OpenEnd),
    Format('<!-- entfernt: %s -->', [AName]))];
end;

class function TDocComments.Actions(const AText: string; ATree: TSyntaxTree; ALine: Integer): TArray<TCodeAction>;
var
  Lines, Existing, Missing: TArray<string>;
  Signature: TDocSignature;
  Action: TCodeAction;
  First, Line, Anchor: Integer;
  Name, LB, Indent, Inserted: string;
  Stale: Boolean;
begin
  Result := nil;
  Lines := TTextLines.SplitLines(AText);
  if not IsDeclarationLine(ATree, Lines, ALine) or IsDocLine(Lines[ALine]) then
    Exit;
  LB := TTextLines.LineBreakOf(AText);
  Indent := TTextLines.IndentOf(Lines[ALine]);
  Signature := TDocComments.Signature(Lines, ALine);
  Action := Default(TCodeAction);
  Action.Kind := RewriteKind;
  First := ALine;
  while (First > 0) and IsDocLine(Lines[First - 1]) do
    Dec(First);
  if First = ALine then
  begin
    Action.Title := 'Dokumentationskommentar erzeugen';
    Action.Edits := [TTextEdit.Create(TTextRange.Create(ALine, 0, ALine, 0),
      TTextLines.JoinLines(TDocComments.Skeleton(Signature, Indent), LB) + LB)];
    Result := [Action];
    Exit;
  end;
  if not Signature.IsRoutine then
    Exit;
  // Vorhandene <param> mit der Signatur abgleichen.
  Existing := nil;
  Stale := False;
  Anchor := First;
  for Line := First to ALine - 1 do
  begin
    Name := ParamName(Lines[Line]);
    if (Name <> '') or ContainsText(Lines[Line], '</summary>') or ContainsText(Lines[Line], '<typeparam') or
      ContainsText(Lines[Line], '</param>') then
      Anchor := Line + 1;
    if Name = '' then
      Continue;
    Existing := Existing + [Name];
    if IndexText(Name, Signature.Params) < 0 then
    begin
      Stale := True;
      Action.Edits := Action.Edits + MarkRemoved(Lines, Line, ALine - 1, Name);
    end;
  end;
  Missing := nil;
  for Name in Signature.Params do
    if IndexText(Name, Existing) < 0 then
      Missing := Missing + [Name];
  if Missing <> nil then
  begin
    Inserted := '';
    for Name in Missing do
      Inserted := Inserted + Indent + Format('/// <param name="%s"></param>', [Name]) + LB;
    Action.Edits := Action.Edits + [TTextEdit.Create(TTextRange.Create(Anchor, 0, Anchor, 0), Inserted)];
  end;
  if Action.Edits = nil then
    Exit;
  if Stale then
    Action.Title := 'Dokumentation an die Signatur anpassen'
  else
    Action.Title := 'Fehlende <param> ergänzen';
  Result := [Action];
end;

end.
