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
// Steht "///" über einer Methodenimplementierung TFoo.Bar, entsteht das Gerüst
// an der Deklaration in der Klasse (vor ihren Attributen), und die Zeile mit
// "///" entfällt. Überladungen unterscheidet Atlas an den Parameternamen.
// "Parameter abgleichen" (Strg+Leer in einem bestehenden Block) liefert
// dieselbe Anpassung wie die Code-Aktion.
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
      out AEdit: TTextEdit): Boolean; overload; static;
    /// <summary>Wie oben; über einer Methodenimplementierung TFoo.Bar das Gerüst an der Deklaration in der
    /// Klasse: AEdits = Gerüst einfügen, Zeile mit "///" löschen. False, wenn die Deklaration schon dokumentiert
    /// ist oder die Zeile nicht passt.</summary>
    class function AfterSlash(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      out AEdits: TArray<TTextEdit>): Boolean; overload; static;
    /// <summary>"Parameter abgleichen" für den ///-Block, in dem Zeile ALine liegt: fehlende &lt;param&gt;
    /// ergänzen, überzählige markieren. False, wenn der Block zu keiner Routine gehört oder schon passt.</summary>
    class function AdjustBlock(const AText: string; ATree: TSyntaxTree; ALine: Integer;
      out AAction: TCodeAction): Boolean; static;
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

type
  TSyntaxKinds = set of TSyntaxKind;

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

/// <summary>Erster Knoten einer der Arten AKinds, der in Zeile ALine beginnt; nil sonst. Search statt
/// Rekursion (Bericht M1); unter ANode nur Knoten, die ALine überdecken.</summary>
function NodeAt(ANode: TSyntaxNode; ALine: Integer; const AKinds: TSyntaxKinds): TSyntaxNode; overload;
var
  Root: TSyntaxNode;
  Line: Integer;
  Kinds: TSyntaxKinds;
begin
  Root := ANode;
  Line := ALine;
  Kinds := AKinds;
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      if (ACandidate <> Root) and ((ACandidate.StartPos.Line > Line) or (ACandidate.EndPos.Line < Line)) then
        Exit(TSyntaxSearchStep.Skip);
      Result := TSyntaxSearchStep.Descend;
      if (ACandidate.Kind in Kinds) and (ACandidate.StartPos.Line = Line) then
        Result := TSyntaxSearchStep.Found;
    end);
end;

function FindDeclaration(ANode: TSyntaxNode; ALine: Integer): Boolean;
begin
  Result := NodeAt(ANode, ALine, DeclarationKinds) <> nil;
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

function IsAttributeLine(const ALine: string): Boolean;
begin
  Result := StartsStr('[', Trim(ALine)) and EndsStr(']', Trim(ALine));
end;

/// <summary>Knoten der Art AKind, der in Zeile ALine beginnt; nil sonst.</summary>
function NodeAt(ANode: TSyntaxNode; ALine: Integer; AKind: TSyntaxKind): TSyntaxNode; overload;
begin
  Result := NodeAt(ANode, ALine, [AKind]);
end;

/// <summary>Typdeklaration AName unter ANode, durch Abschnitte und Typrümpfe, nicht in andere Typen hinein.
/// </summary>
function FindType(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
const
  Containers = [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection, TSyntaxKind.TypeSection,
    TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType, TSyntaxKind.HelperType];
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Result := ANode[Index];
    if (Result.Kind = TSyntaxKind.TypeDecl) and SameText(Result.Name, AName) then
      Exit;
    if Result.Kind in Containers then
    begin
      Result := FindType(Result, AName);
      if Result <> nil then
        Exit;
    end;
  end;
  Result := nil;
end;

/// <summary>Parameternamen eines RoutineHeader-Knotens in Reihenfolge.</summary>
function HeaderParams(AHeader: TSyntaxNode): TArray<string>;
var
  Parameters: TSyntaxNode;
  Index: Integer;
  Name: string;
begin
  Result := nil;
  Parameters := AHeader.FindChild(TSyntaxKind.Parameters);
  if Parameters = nil then
    Exit;
  for Index := 0 to Parameters.ChildCount - 1 do
    if Parameters[Index].Kind = TSyntaxKind.Parameter then
      for Name in Parameters[Index].Name.Split([',']) do
        Result := Result + [Trim(Name)];
end;

function SameNames(const A, B: TArray<string>): Boolean;
var
  Index: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for Index := 0 to High(A) do
      if not SameText(A[Index], B[Index]) then
        Exit(False);
end;

/// <summary>Deklaration (RoutineHeader in der Klasse) zur Methodenimplementierung in Zeile ALine; nil, wenn die
/// Zeile keine Methode TFoo.Bar beginnt oder die Deklaration fehlt bzw. nicht eindeutig ist.</summary>
function MethodDeclaration(ATree: TSyntaxTree; const ALines: TArray<string>; ALine: Integer): TSyntaxNode;
var
  Routine, Body, Member, Found: TSyntaxNode;
  Parts: TArray<string>;
  Params: TArray<string>;
  Index, Count: Integer;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Routine := NodeAt(ATree.Root, ALine, TSyntaxKind.RoutineDecl);
  if (Routine = nil) or (Pos('.', Routine.Name) = 0) then
    Exit;
  Parts := Routine.Name.Split(['.']);
  Found := ATree.Root;
  for Index := 0 to High(Parts) - 1 do
  begin
    Found := FindType(Found, Parts[Index]);
    if Found = nil then
      Exit;
  end;
  Body := nil;
  for Index := 0 to Found.ChildCount - 1 do
    if Found[Index].Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
      TSyntaxKind.HelperType] then
      Body := Found[Index];
  if Body = nil then
    Exit;
  Params := TDocComments.Signature(ALines, ALine).Params;
  Count := 0;
  for Index := 0 to Body.ChildCount - 1 do
  begin
    Member := Body[Index];
    if (Member.Kind <> TSyntaxKind.RoutineHeader) or not SameText(Member.Name, Parts[High(Parts)]) then
      Continue;
    // Überladung: an den Parameternamen erkennen.
    if SameNames(HeaderParams(Member), Params) then
      Exit(Member);
    Inc(Count);
    Result := Member;
  end;
  if Count <> 1 then
    Result := nil;
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

class function TDocComments.AfterSlash(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  Lines: TArray<string>;
  Line, Target: Integer;
  Declaration: TSyntaxNode;
  Edit: TTextEdit;
  LB: string;
begin
  AEdits := nil;
  Lines := TTextLines.SplitLines(AText);
  Line := APosition.Line;
  Declaration := nil;
  if (Line >= 0) and (Line < High(Lines)) and (Trim(Lines[Line]) = '///') and
    not ((Line > 0) and IsDocLine(Lines[Line - 1])) then
    Declaration := MethodDeclaration(ATree, Lines, Line + 1);
  if Declaration = nil then
  begin
    Result := TDocComments.AfterSlash(AText, ATree, APosition, Edit);
    if Result then
      AEdits := [Edit];
    Exit;
  end;
  // Über den Attributen der Deklaration einfügen.
  Target := Declaration.StartPos.Line;
  while (Target > 0) and IsAttributeLine(Lines[Target - 1]) do
    Dec(Target);
  // Schon dokumentiert: "///" bleibt, wie getippt.
  Result := not ((Target > 0) and IsDocLine(Lines[Target - 1]));
  if not Result then
    Exit;
  LB := TTextLines.LineBreakOf(AText);
  AEdits := [TTextEdit.Create(TTextRange.Create(Target, 0, Target, 0),
    TTextLines.JoinLines(TDocComments.Skeleton(TDocComments.Signature(Lines, Declaration.StartPos.Line),
    TTextLines.IndentOf(Lines[Declaration.StartPos.Line])), LB) + LB),
    TTextEdit.Create(TTextRange.Create(Line, 0, Line + 1, 0), '')];
end;

class function TDocComments.AdjustBlock(const AText: string; ATree: TSyntaxTree; ALine: Integer;
  out AAction: TCodeAction): Boolean;
var
  Lines: TArray<string>;
  Line: Integer;
  Actions: TArray<TCodeAction>;
begin
  Result := False;
  AAction := Default(TCodeAction);
  Lines := TTextLines.SplitLines(AText);
  if (ALine < 0) or (ALine > High(Lines)) or not IsDocLine(Lines[ALine]) then
    Exit;
  Line := ALine;
  while (Line <= High(Lines)) and IsDocLine(Lines[Line]) do
    Inc(Line);
  while (Line <= High(Lines)) and IsAttributeLine(Lines[Line]) do
    Inc(Line);
  if Line > High(Lines) then
    Exit;
  Actions := TDocComments.Actions(AText, ATree, Line);
  // Ohne Block liefert Actions "erzeugen"; hier steht ein Block, also nur der Abgleich.
  Result := Actions <> nil;
  if Result then
  begin
    AAction := Actions[0];
    AAction.Title := 'Parameter abgleichen';
  end;
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
  Top, First, Line, Anchor: Integer;
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
  // Der Kommentar steht über den Attributen der Deklaration.
  Top := ALine;
  while (Top > 0) and IsAttributeLine(Lines[Top - 1]) do
    Dec(Top);
  First := Top;
  while (First > 0) and IsDocLine(Lines[First - 1]) do
    Dec(First);
  if First = Top then
  begin
    Action.Title := 'Dokumentationskommentar erzeugen';
    Action.Edits := [TTextEdit.Create(TTextRange.Create(Top, 0, Top, 0),
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
  for Line := First to Top - 1 do
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
      Action.Edits := Action.Edits + MarkRemoved(Lines, Line, Top - 1, Name);
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
