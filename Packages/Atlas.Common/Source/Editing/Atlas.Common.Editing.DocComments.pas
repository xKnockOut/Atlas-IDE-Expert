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
    begin
      Text := Copy(Text, 1, Pos('//', Text) - 1);
    end;
    for Index := 1 to Length(Text) do
    begin
      case Text[Index] of
        '(':
          Inc(Depth);
        ')':
          Dec(Depth);
        ';':
          if Depth = 0 then
          begin
            Exit(Result + Copy(Text, 1, Index));
          end;
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
  begin
    Text := Copy(Text, 1, Colon - 1);
  end;
  // Attribute wie [Ref] entfernen.
  Bracket := Pos(']', Text);
  if (Pos('[', Text) > 0) and (Bracket > 0) then
  begin
    Text := Copy(Text, 1, Pos('[', Text) - 1) + Copy(Text, Bracket + 1, MaxInt);
  end;
  Text := Trim(Text);
  for Name in ['const ', 'var ', 'out ', 'constref '] do
  begin
    if StartsText(Name, Text) then
    begin
      Text := Trim(Copy(Text, Length(Name) + 1, MaxInt));
    end;
  end;
  for Name in SplitTop(Text, ',') do
  begin
    if IsValidIdent(Trim(Name)) then
    begin
      Result := Result + [Trim(Name)];
    end;
  end;
end;

/// <summary>Text der Routinendeklaration ab ALine hinter "class" und dem Schlüsselwort; False, wenn dort keine
/// Routine beginnt. AWord: function, procedure, constructor, destructor oder operator.</summary>
function RoutineText(const ALines: TArray<string>; ALine: Integer; out AWord, AText: string): Boolean;
begin
  AText := Trim(DeclarationText(ALines, ALine));
  if StartsText('class ', AText) then
  begin
    AText := Trim(Copy(AText, 7, MaxInt));
  end;
  AWord := LowerCase(Copy(AText, 1, Pos(' ', AText + ' ') - 1));
  Result := IndexText(AWord, RoutineWords) >= 0;
  if Result then
  begin
    AText := Trim(Copy(AText, Length(AWord) + 1, MaxInt));
  end;
end;

/// <summary>Name der Routine mit generischen Parametern, ohne Parameterliste und Ergebnistyp.</summary>
function RoutineHead(const AText: string; AOpen: Integer): string;
begin
  if AOpen = 0 then
  begin
    Result := Copy(AText, 1, Pos(';', AText + ';') - 1);
  end
  else
  begin
    Result := Copy(AText, 1, AOpen - 1);
  end;
  if Pos(':', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos(':', Result) - 1);
  end;
end;

/// <summary>Generische Parameter am Namen (nicht am Klassennamen davor).</summary>
function TypeParamsOf(const AHead: string): TArray<string>;
var
  mLess: Integer;
  mPart, mName: string;
begin
  Result := nil;
  mLess := LastDelimiter('<', AHead);
  if (mLess = 0) or (mLess < LastDelimiter('.', AHead)) then
  begin
    Exit;
  end;
  for mPart in SplitTop(StringReplace(Copy(AHead, mLess + 1, LastDelimiter('>', AHead) - mLess - 1), ';', ',',
    [rfReplaceAll]), ',') do
  begin
    mName := Trim(Copy(mPart, 1, Pos(':', mPart + ':') - 1));
    if IsValidIdent(mName) then
    begin
      Result := Result + [mName];
    end;
  end;
end;

/// <summary>Index der schließenden Klammer zur öffnenden an AOpen; 0, wenn sie fehlt.</summary>
function ClosingParen(const AText: string; AOpen: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  Result := AOpen;
  while Result <= Length(AText) do
  begin
    if AText[Result] = '(' then
    begin
      Inc(mDepth);
    end
    else if AText[Result] = ')' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end;
    Inc(Result);
  end;
  Result := 0;
end;

/// <summary>Parameternamen der Liste, die an AOpen beginnt; leer ohne Liste.</summary>
function ParamsOf(const AText: string; AOpen: Integer): TArray<string>;
var
  mClose: Integer;
  mPart: string;
begin
  Result := nil;
  mClose := 0;
  if AOpen > 0 then
  begin
    mClose := ClosingParen(AText, AOpen);
  end;
  if mClose = 0 then
  begin
    Exit;
  end;
  for mPart in SplitTop(Copy(AText, AOpen + 1, mClose - AOpen - 1), ';') do
  begin
    Result := Result + GroupNames(mPart);
  end;
end;

class function TDocComments.Signature(const ALines: TArray<string>; ALine: Integer): TDocSignature;
var
  mWord, mText: string;
  mOpen: Integer;
begin
  Result := Default(TDocSignature);
  if not RoutineText(ALines, ALine, mWord, mText) then
  begin
    Exit;
  end;
  Result.IsRoutine := True;
  Result.HasResult := MatchText(mWord, ['function', 'operator']);
  mOpen := Pos('(', mText);
  Result.TypeParams := TypeParamsOf(RoutineHead(mText, mOpen));
  Result.Params := ParamsOf(mText, mOpen);
end;

class function TDocComments.Skeleton(const ASignature: TDocSignature; const AIndent: string): TArray<string>;
var
  Name: string;
begin
  Result := [AIndent + '/// <summary></summary>'];
  for Name in ASignature.TypeParams do
  begin
    Result := Result + [AIndent + Format('/// <typeparam name="%s"></typeparam>', [Name])];
  end;
  for Name in ASignature.Params do
  begin
    Result := Result + [AIndent + Format('/// <param name="%s"></param>', [Name])];
  end;
  if ASignature.HasResult then
  begin
    Result := Result + [AIndent + '/// <returns></returns>'];
  end;
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
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      Result := TSyntaxSearchStep.Descend;
      if (ACandidate.Kind in Kinds) and (ACandidate.StartPos.Line = Line) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
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
    begin
      Exit;
    end;
    if Result.Kind in Containers then
    begin
      Result := FindType(Result, AName);
      if Result <> nil then
      begin
        Exit;
      end;
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
  begin
    Exit;
  end;
  for Index := 0 to Parameters.ChildCount - 1 do
  begin
    if Parameters[Index].Kind = TSyntaxKind.Parameter then
    begin
      for Name in Parameters[Index].Name.Split([',']) do
      begin
        Result := Result + [Trim(Name)];
      end;
    end;
  end;
end;

function SameNames(const A, B: TArray<string>): Boolean;
var
  Index: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
  begin
    for Index := 0 to High(A) do
    begin
      if not SameText(A[Index], B[Index]) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

/// <summary>Rumpf (Klasse, Objekt, Record, Helfer) des Typs, dessen Methode AParts benennt ("TFoo.Bar",
/// "TFoo.TInner.Bar" zerlegt an den Punkten); nil, wenn er fehlt.</summary>
function TypeBody(ARoot: TSyntaxNode; const AParts: TArray<string>): TSyntaxNode;
var
  mType: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mType := ARoot;
  mIndex := 0;
  while (mType <> nil) and (mIndex < High(AParts)) do
  begin
    mType := FindType(mType, AParts[mIndex]);
    Inc(mIndex);
  end;
  if mType = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mType.ChildCount - 1 do
  begin
    if mType[mIndex].Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
      TSyntaxKind.HelperType] then
    begin
      Result := mType[mIndex];
    end;
  end;
end;

/// <summary>Deklaration AName in ABody: bei Überladungen die mit den Parameternamen AParams, sonst die einzige;
/// nil, wenn sie fehlt oder nicht eindeutig ist.</summary>
function MatchingHeader(ABody: TSyntaxNode; const AName: string; const AParams: TArray<string>): TSyntaxNode;
var
  mMember: TSyntaxNode;
  mIndex, mCount: Integer;
begin
  Result := nil;
  mCount := 0;
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    mMember := ABody[mIndex];
    if (mMember.Kind = TSyntaxKind.RoutineHeader) and SameText(mMember.Name, AName) then
    begin
      // Überladung: an den Parameternamen erkennen.
      if SameNames(HeaderParams(mMember), AParams) then
      begin
        Exit(mMember);
      end;
      Inc(mCount);
      Result := mMember;
    end;
  end;
  if mCount <> 1 then
  begin
    Result := nil;
  end;
end;

/// <summary>Deklaration (RoutineHeader in der Klasse) zur Methodenimplementierung in Zeile ALine; nil, wenn die
/// Zeile keine Methode TFoo.Bar beginnt oder die Deklaration fehlt bzw. nicht eindeutig ist.</summary>
function MethodDeclaration(ATree: TSyntaxTree; const ALines: TArray<string>; ALine: Integer): TSyntaxNode;
var
  mRoutine, mBody: TSyntaxNode;
  mParts: TArray<string>;
begin
  Result := nil;
  mRoutine := nil;
  if (ATree <> nil) and (ATree.Root <> nil) then
  begin
    mRoutine := NodeAt(ATree.Root, ALine, TSyntaxKind.RoutineDecl);
  end;
  if (mRoutine = nil) or (Pos('.', mRoutine.Name) = 0) then
  begin
    Exit;
  end;
  mParts := mRoutine.Name.Split(['.']);
  mBody := TypeBody(ATree.Root, mParts);
  if mBody <> nil then
  begin
    Result := MatchingHeader(mBody, mParts[High(mParts)], TDocComments.Signature(ALines, ALine).Params);
  end;
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
  begin
    Exit;
  end;
  // Schon dokumentiert oder kein Ziel darunter.
  if ((Line > 0) and IsDocLine(Lines[Line - 1])) or not IsDeclarationLine(ATree, Lines, Line + 1) then
  begin
    Exit;
  end;
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
  begin
    Declaration := MethodDeclaration(ATree, Lines, Line + 1);
  end;
  if Declaration = nil then
  begin
    Result := TDocComments.AfterSlash(AText, ATree, APosition, Edit);
    if Result then
    begin
      AEdits := [Edit];
    end;
    Exit;
  end;
  // Über den Attributen der Deklaration einfügen.
  Target := Declaration.StartPos.Line;
  while (Target > 0) and IsAttributeLine(Lines[Target - 1]) do
  begin
    Dec(Target);
  end;
  // Schon dokumentiert: "///" bleibt, wie getippt.
  Result := not ((Target > 0) and IsDocLine(Lines[Target - 1]));
  if not Result then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  Line := ALine;
  while (Line <= High(Lines)) and IsDocLine(Lines[Line]) do
  begin
    Inc(Line);
  end;
  while (Line <= High(Lines)) and IsAttributeLine(Lines[Line]) do
  begin
    Inc(Line);
  end;
  if Line > High(Lines) then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  Start := Start + Length('<param name="');
  Stop := PosEx('"', ALine, Start);
  if Stop > Start then
  begin
    Result := Copy(ALine, Start, Stop - Start);
  end;
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
    begin
      Description := ': ' + Description;
    end;
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

/// <summary>Erste Zeile über den Attributen der Deklaration in Zeile ALine.</summary>
function AboveAttributes(const ALines: TArray<string>; ALine: Integer): Integer;
begin
  Result := ALine;
  while (Result > 0) and IsAttributeLine(ALines[Result - 1]) do
  begin
    Dec(Result);
  end;
end;

type
  /// <summary>///-Block über einer Deklaration: Zeilen First..Top - 1 (leer bei First = Top).</summary>
  TDocBlock = record
    Lines: TArray<string>;
    First: Integer;
    Top: Integer;
    Indent: string;
    LineBreak: string;
    class function Create(const AText: string; const ALines: TArray<string>; ALine: Integer): TDocBlock; static;
    /// <summary>Zeile hinter dem letzten &lt;summary&gt;, &lt;typeparam&gt; oder &lt;param&gt;.</summary>
    function Anchor: Integer;
    function ExistingParams: TArray<string>;
    /// <summary>&lt;param&gt; ohne Parameter in AParams als entfernt markieren.</summary>
    function MarkStale(const AParams: TArray<string>): TArray<TTextEdit>;
    /// <summary>Fehlende &lt;param&gt; aus AParams am Anker einfügen; leer, wenn keiner fehlt.</summary>
    function InsertMissing(const AParams: TArray<string>): TArray<TTextEdit>;
  end;

class function TDocBlock.Create(const AText: string; const ALines: TArray<string>; ALine: Integer): TDocBlock;
begin
  Result.Lines := ALines;
  Result.Indent := TTextLines.IndentOf(ALines[ALine]);
  Result.LineBreak := TTextLines.LineBreakOf(AText);
  // Der Kommentar steht über den Attributen der Deklaration.
  Result.Top := AboveAttributes(ALines, ALine);
  Result.First := Result.Top;
  while (Result.First > 0) and IsDocLine(ALines[Result.First - 1]) do
  begin
    Dec(Result.First);
  end;
end;

function TDocBlock.Anchor: Integer;
var
  mLine: Integer;
begin
  Result := First;
  for mLine := First to Top - 1 do
  begin
    if (ParamName(Lines[mLine]) <> '') or ContainsText(Lines[mLine], '</summary>') or
      ContainsText(Lines[mLine], '<typeparam') or ContainsText(Lines[mLine], '</param>') then
    begin
      Result := mLine + 1;
    end;
  end;
end;

function TDocBlock.ExistingParams: TArray<string>;
var
  mLine: Integer;
begin
  Result := nil;
  for mLine := First to Top - 1 do
  begin
    if ParamName(Lines[mLine]) <> '' then
    begin
      Result := Result + [ParamName(Lines[mLine])];
    end;
  end;
end;

function TDocBlock.MarkStale(const AParams: TArray<string>): TArray<TTextEdit>;
var
  mLine: Integer;
  mName: string;
begin
  Result := nil;
  for mLine := First to Top - 1 do
  begin
    mName := ParamName(Lines[mLine]);
    if (mName <> '') and (IndexText(mName, AParams) < 0) then
    begin
      Result := Result + MarkRemoved(Lines, mLine, Top - 1, mName);
    end;
  end;
end;

function TDocBlock.InsertMissing(const AParams: TArray<string>): TArray<TTextEdit>;
var
  mExisting: TArray<string>;
  mName, mInserted: string;
begin
  Result := nil;
  mExisting := ExistingParams;
  mInserted := '';
  for mName in AParams do
  begin
    if IndexText(mName, mExisting) < 0 then
    begin
      mInserted := mInserted + Indent + Format('/// <param name="%s"></param>', [mName]) + LineBreak;
    end;
  end;
  if mInserted <> '' then
  begin
    Result := [TTextEdit.Create(TTextRange.Create(Anchor, 0, Anchor, 0), mInserted)];
  end;
end;

class function TDocComments.Actions(const AText: string; ATree: TSyntaxTree; ALine: Integer): TArray<TCodeAction>;
var
  mLines: TArray<string>;
  mSignature: TDocSignature;
  mBlock: TDocBlock;
  mStale: TArray<TTextEdit>;
  mAction: TCodeAction;
begin
  Result := nil;
  mLines := TTextLines.SplitLines(AText);
  if not IsDeclarationLine(ATree, mLines, ALine) or IsDocLine(mLines[ALine]) then
  begin
    Exit;
  end;
  mSignature := TDocComments.Signature(mLines, ALine);
  mBlock := TDocBlock.Create(AText, mLines, ALine);
  mAction := Default(TCodeAction);
  mAction.Kind := RewriteKind;
  if mBlock.First = mBlock.Top then
  begin
    mAction.Title := 'Dokumentationskommentar erzeugen';
    mAction.Edits := [TTextEdit.Create(TTextRange.Create(mBlock.Top, 0, mBlock.Top, 0),
      TTextLines.JoinLines(TDocComments.Skeleton(mSignature, mBlock.Indent), mBlock.LineBreak) + mBlock.LineBreak)];
  end
  else if mSignature.IsRoutine then
  begin
    // Vorhandene <param> mit der Signatur abgleichen.
    mStale := mBlock.MarkStale(mSignature.Params);
    mAction.Edits := mStale + mBlock.InsertMissing(mSignature.Params);
    mAction.Title := 'Fehlende <param> ergänzen';
    if mStale <> nil then
    begin
      mAction.Title := 'Dokumentation an die Signatur anpassen';
    end;
  end;
  if mAction.Edits <> nil then
  begin
    Result := [mAction];
  end;
end;

end.
