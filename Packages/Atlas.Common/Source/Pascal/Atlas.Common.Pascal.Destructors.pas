unit Atlas.Common.Pascal.Destructors;

// Anweisungen in den Destruktor einer Klasse setzen (#666, #944, #971), rein syntaktisch:
//   - Freigabe: vor dem ersten inherited im Destruktor, sonst vor dessen
//     "end", in umgekehrter Erzeugungsreihenfolge, als FFeld.Free oder
//     FreeAndNil(FFeld). Fehlt der Destruktor, kommt "destructor Destroy;
//     override;" in den public-Abschnitt (hinter den Konstruktor, sonst ans
//     Ende des letzten public-Abschnitts, sonst in einen neuen) und der Rumpf
//     mit inherited hinter den letzten Konstruktor.
//   - class destructor: vor dessen "end"; fehlt er, wird er hinter dem class
//     constructor deklariert und angelegt.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  {$SCOPEDENUMS ON}
  /// <summary>Form der Freigabe: FFeld.Free oder FreeAndNil(FFeld).</summary>
  TFreeFieldsStyle = (Free, FreeAndNil);
  {$SCOPEDENUMS OFF}

  TPascalDestructors = class
  public
    /// <summary>Stil aus dem Wert der Einstellung: freeAndNil, sonst Free.</summary>
    class function StyleOf(const AName: string): TFreeFieldsStyle; static;
    /// <summary>"FFeld.Free;" bzw. "FreeAndNil(FFeld);".</summary>
    class function Statement(const AField: string; AStyle: TFreeFieldsStyle): string; static;
    /// <summary>AStatements in den Destruktor der Klasse AClassName (Kopfzeile ALine): vor das erste inherited,
    /// sonst vor "end"; fehlt er, wird er hinter dem letzten Konstruktor angelegt (#944). False ohne Klasse oder
    /// ohne Destruktor und Konstruktor.</summary>
    class function DestructorEdits(ATree: TSyntaxTree; const AText, AClassName: string; ALine: Integer;
      const AStatements: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>AStatements in den class destructor der Klasse AClassDecl, vor dessen "end"; fehlt er, wird er
    /// hinter dem class constructor deklariert und angelegt (#971). False ohne class constructor bzw. wenn
    /// kein Platz zu finden ist.</summary>
    class function ClassDestructorEdits(ATree: TSyntaxTree; const AText: string; AClassDecl: TSyntaxNode;
      const AStatements: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>Rümpfe der Methoden TKlasse.Name von AClassName im implementation-Abschnitt bzw. in der
    /// Programmdatei, in Textreihenfolge.</summary>
    class function ClassMethods(ATree: TSyntaxTree; const AClassName: string): TArray<TSyntaxNode>; static;
    /// <summary>Ist ADecl der Rumpf eines Konstruktors?</summary>
    class function IsConstructor(const AText: string; ADecl: TSyntaxNode): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Lines;

/// <summary>Quelltext eines Knotens.</summary>
function NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Routinen der Datei: implementation-Abschnitt bzw. Programmdatei.</summary>
function RoutineDecls(ATree: TSyntaxTree): TArray<TSyntaxNode>;
var
  mSection: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mSection := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if mSection = nil then
  begin
    mSection := ATree.Root;
  end;
  for mIndex := 0 to mSection.ChildCount - 1 do
  begin
    if mSection[mIndex].Kind = TSyntaxKind.RoutineDecl then
    begin
      Result := Result + [mSection[mIndex]];
    end;
  end;
end;

/// <summary>Methoden TKlasse.Name mit Rumpf, ohne Methoden verschachtelter Klassen.</summary>
function MethodBodies(ATree: TSyntaxTree; const AClassName: string): TArray<TSyntaxNode>;
var
  mDecl: TSyntaxNode;
  mRest: string;
begin
  Result := nil;
  for mDecl in RoutineDecls(ATree) do
  begin
    if StartsText(AClassName + '.', mDecl.Name) and (mDecl.FindChild(TSyntaxKind.Block) <> nil) then
    begin
      mRest := Copy(mDecl.Name, Length(AClassName) + 2, MaxInt);
      if (mRest <> '') and (Pos('.', mRest) = 0) then
      begin
        Result := Result + [mDecl];
      end;
    end;
  end;
end;

function HeaderOf(ADecl: TSyntaxNode): TSyntaxNode;
begin
  Result := ADecl.FindChild(TSyntaxKind.RoutineHeader);
end;

function StartsWithWord(const AText, AWord: string): Boolean;
var
  mText: string;
begin
  mText := TrimLeft(AText);
  Result := StartsText(AWord, mText) and ((Length(mText) = Length(AWord)) or
    not CharInSet(mText[Length(AWord) + 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']));
end;

function IsConstructorDecl(const AText: string; ADecl: TSyntaxNode): Boolean;
var
  mHeader: TSyntaxNode;
begin
  mHeader := HeaderOf(ADecl);
  Result := (mHeader <> nil) and StartsWithWord(NodeText(AText, mHeader), 'constructor');
end;

function IsDestructorHeader(const AText: string; AHeader: TSyntaxNode): Boolean;
begin
  Result := (AHeader <> nil) and SameText(AHeader.Name, 'Destroy') and
    StartsWithWord(NodeText(AText, AHeader), 'destructor');
end;

{ Destruktor }

type
  TDestructorPlace = record
    /// <summary>Deklaration in der Klasse; nil ohne.</summary>
    Declaration: TSyntaxNode;
    /// <summary>Rumpf TKlasse.Destroy; nil ohne.</summary>
    Body: TSyntaxNode;
    /// <summary>Letzter Konstruktor-Rumpf der Klasse; nil ohne.</summary>
    LastConstructor: TSyntaxNode;
  end;

function FindClassDecl(ATree: TSyntaxTree; const AClassName: string; ALine: Integer): TSyntaxNode;
var
  mFound: TSyntaxNode;
begin
  mFound := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := mFound = nil;
      if Result and (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.StartPos.Line = ALine) and
        SameText(ANode.Name, AClassName) and (ANode.FindChild(TSyntaxKind.ClassType) <> nil) then
      begin
        mFound := ANode;
      end;
    end);
  Result := mFound;
end;

function PlaceOf(ATree: TSyntaxTree; const AText: string; ADecl: TSyntaxNode): TDestructorPlace;
var
  mClassNode, mHeader, mDecl: TSyntaxNode;
  mIndex: Integer;
begin
  Result := Default(TDestructorPlace);
  mClassNode := ADecl.FindChild(TSyntaxKind.ClassType);
  for mIndex := 0 to mClassNode.ChildCount - 1 do
  begin
    if IsDestructorHeader(AText, mClassNode[mIndex]) and (mClassNode[mIndex].Kind = TSyntaxKind.RoutineHeader) then
    begin
      Result.Declaration := mClassNode[mIndex];
    end;
  end;
  for mDecl in MethodBodies(ATree, ADecl.Name) do
  begin
    mHeader := HeaderOf(mDecl);
    if SameText(mDecl.Name, ADecl.Name + '.Destroy') and (mHeader <> nil) and
      StartsWithWord(NodeText(AText, mHeader), 'destructor') then
    begin
      Result.Body := mDecl;
    end
    else if IsConstructorDecl(AText, mDecl) then
    begin
      Result.LastConstructor := mDecl;
    end;
  end;
end;

/// <summary>Klassenname des Rumpfs samt generischer Parameter: "constructor TFoo&lt;T&gt;.Create(…)" →
/// TFoo&lt;T&gt;.</summary>
function Qualifier(const AText: string; AConstructor: TSyntaxNode; const AClassName: string): string;
var
  mHeader: string;
  mStop: Integer;
begin
  // Text vom Anfang der Routine bis zum Block; der Kopfknoten generischer Klassen deckt nicht alles ab.
  mHeader := TTextLines.CollapseSpace(Copy(AText, AConstructor.StartOffset + 1,
    AConstructor.FindChild(TSyntaxKind.Block).StartOffset - AConstructor.StartOffset));
  // "constructor" bzw. "class constructor" (#971) abschneiden.
  mHeader := Trim(Copy(mHeader, Pos('constructor', LowerCase(mHeader)) + Length('constructor'), MaxInt));
  mStop := Pos('(', mHeader);
  if mStop = 0 then
  begin
    mStop := Pos(';', mHeader);
  end;
  if mStop > 0 then
  begin
    mHeader := Copy(mHeader, 1, mStop - 1);
  end;
  mStop := LastDelimiter('.', mHeader);
  Result := AClassName;
  if mStop > 1 then
  begin
    Result := Trim(Copy(mHeader, 1, mStop - 1));
  end;
end;

function IsInheritedCall(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount >= 1) and
    (ANode[0].Kind = TSyntaxKind.InheritedExpr);
end;

function InsertAt(const APosition: TTextPosition; const AText: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(APosition, APosition), AText);
end;

/// <summary>Freigaben in den vorhandenen Rumpf: vor das erste inherited, sonst vor "end".</summary>
function BodyEdit(const ALines: TArray<string>; ABody: TSyntaxNode; const AStatements: TArray<string>;
  const ALineBreak: string): TTextEdit;
var
  mBlock, mChild, mAnchor: TSyntaxNode;
  mIndex: Integer;
  mPosition: TTextPosition;
  mPrefix, mIndent, mText, mStatement: string;
begin
  mBlock := ABody.FindChild(TSyntaxKind.Block);
  mAnchor := nil;
  for mIndex := 0 to mBlock.ChildCount - 1 do
  begin
    mChild := mBlock[mIndex];
    if IsInheritedCall(mChild) then
    begin
      mAnchor := mChild;
      Break;
    end;
  end;
  if mAnchor <> nil then
  begin
    mPosition := mAnchor.StartPos;
    mIndent := '';
  end
  else
  begin
    // "end" des Blocks: drei Zeichen vor dessen Ende.
    mPosition := TTextPosition.Create(mBlock.EndPos.Line, mBlock.EndPos.Character - 3);
    mIndent := '  ';
  end;
  mPrefix := '';
  if mPosition.Line <= High(ALines) then
  begin
    mPrefix := Copy(ALines[mPosition.Line], 1, mPosition.Character);
  end;
  mText := '';
  if Trim(mPrefix) = '' then
  begin
    // Eigene Zeilen vor der Ankerzeile, eingerückt wie sie (bzw. eine Stufe tiefer als "end").
    mIndent := mPrefix + mIndent;
    for mStatement in AStatements do
    begin
      mText := mText + mIndent + mStatement + ALineBreak;
    end;
    Result := InsertAt(TTextPosition.Create(mPosition.Line, 0), mText);
  end
  else
  begin
    for mStatement in AStatements do
    begin
      mText := mText + mStatement + ' ';
    end;
    Result := InsertAt(mPosition, mText);
  end;
end;

function IsConstructorHeader(const AText: string; AChild: TSyntaxNode): Boolean;
begin
  Result := (AChild.Kind = TSyntaxKind.RoutineHeader) and
    StartsWithWord(NodeText(AText, AChild), 'constructor');
end;

/// <summary>Mitglied im public-Abschnitt, hinter das der Destruktor kommt: der letzte Konstruktor, sonst das
/// letzte Mitglied; nil ohne. APublicHead: das Schlüsselwort des letzten public-Abschnitts.</summary>
function PublicAnchor(const AText: string; AClassNode: TSyntaxNode; out APublicHead: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
  mChild, mAfterConstructor: TSyntaxNode;
  mInPublic: Boolean;
begin
  Result := nil;
  mAfterConstructor := nil;
  APublicHead := nil;
  mInPublic := False;
  for mIndex := 0 to AClassNode.ChildCount - 1 do
  begin
    mChild := AClassNode[mIndex];
    if mChild.Kind = TSyntaxKind.Visibility then
    begin
      mInPublic := SameText(mChild.Name, 'public');
      if mInPublic then
      begin
        APublicHead := mChild;
        Result := nil;
      end;
    end
    else if mInPublic and (mChild.Kind <> TSyntaxKind.TypeReference) then
    begin
      Result := mChild;
      if IsConstructorHeader(AText, mChild) then
      begin
        mAfterConstructor := mChild;
      end;
    end;
  end;
  if mAfterConstructor <> nil then
  begin
    Result := mAfterConstructor;
  end;
end;

/// <summary>AText am Ende der Zeile ALine einfügen.</summary>
function AppendLine(const ALines: TArray<string>; ALine: Integer; const AText: string): TTextEdit;
begin
  Result := InsertAt(TTextPosition.Create(ALine, Length(ALines[ALine])), AText);
end;

/// <summary>"destructor Destroy; override;" in den public-Abschnitt; False, wenn kein Platz zu finden ist.</summary>
function DeclarationEdit(const ALines: TArray<string>; const AText: string; ADecl: TSyntaxNode;
  const ALineBreak: string; out AEdit: TTextEdit): Boolean;
const
  cDeclaration = 'destructor Destroy; override;';
var
  mClassNode, mLast, mHead: TSyntaxNode;
  mLine: Integer;
  mIndent: string;
begin
  mClassNode := ADecl.FindChild(TSyntaxKind.ClassType);
  mLast := PublicAnchor(AText, mClassNode, mHead);
  if mLast <> nil then
  begin
    AEdit := AppendLine(ALines, mLast.EndPos.Line, ALineBreak + TTextLines.IndentOf(ALines[mLast.StartPos.Line]) +
      cDeclaration);
    Exit(True);
  end;
  if mHead <> nil then
  begin
    AEdit := AppendLine(ALines, mHead.EndPos.Line, ALineBreak + TTextLines.IndentOf(ALines[mHead.StartPos.Line]) +
      '  ' + cDeclaration);
    Exit(True);
  end;
  // Neuer Abschnitt vor dem "end" der Klasse, wenn es allein auf seiner Zeile steht.
  mLine := mClassNode.EndPos.Line;
  Result := (mLine <= High(ALines)) and (Trim(Copy(ALines[mLine], 1, mClassNode.EndPos.Character - 3)) = '');
  if Result then
  begin
    mIndent := TTextLines.IndentOf(ALines[mLine]);
    AEdit := InsertAt(TTextPosition.Create(mLine, 0), mIndent + 'public' + ALineBreak + mIndent + '  ' +
      cDeclaration + ALineBreak);
  end;
end;

/// <summary>Routine mit Kopf AHeader und den Anweisungen AStatements, eingerückt um AIndent.</summary>
function RoutineText(const AIndent, AHeader: string; const AStatements: TArray<string>;
  const ALineBreak: string): string;
var
  mStatement: string;
begin
  Result := AIndent + AHeader + ALineBreak + AIndent + 'begin';
  for mStatement in AStatements do
  begin
    Result := Result + ALineBreak + AIndent + '  ' + mStatement;
  end;
  Result := Result + ALineBreak + AIndent + 'end;';
end;

/// <summary>Neuer Destruktor hinter dem letzten Konstruktor, samt Deklaration, wenn sie fehlt.</summary>
function NewDestructor(const AText: string; ADecl: TSyntaxNode; const APlace: TDestructorPlace;
  const AStatements: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean;
var
  mLines: TArray<string>;
  mLineBreak, mHeader: string;
  mEdit: TTextEdit;
begin
  AEdits := nil;
  if APlace.LastConstructor = nil then
  begin
    Exit(False);
  end;
  mLines := TTextLines.SplitLines(AText, mLineBreak);
  if APlace.Declaration = nil then
  begin
    if not DeclarationEdit(mLines, AText, ADecl, mLineBreak, mEdit) then
    begin
      Exit(False);
    end;
    AEdits := [mEdit];
  end;
  mHeader := Format('destructor %s.Destroy;', [Qualifier(AText, APlace.LastConstructor, ADecl.Name)]);
  AEdits := AEdits + [InsertAt(APlace.LastConstructor.EndPos, mLineBreak + mLineBreak +
    RoutineText(StringOfChar(' ', APlace.LastConstructor.StartPos.Character), mHeader, AStatements + ['inherited;'],
    mLineBreak))];
  Result := True;
end;

{ TPascalDestructors }

class function TPascalDestructors.StyleOf(const AName: string): TFreeFieldsStyle;
begin
  if SameText(AName, 'freeAndNil') then
  begin
    Result := TFreeFieldsStyle.FreeAndNil;
  end
  else
  begin
    Result := TFreeFieldsStyle.Free;
  end;
end;

class function TPascalDestructors.Statement(const AField: string; AStyle: TFreeFieldsStyle): string;
begin
  if AStyle = TFreeFieldsStyle.FreeAndNil then
  begin
    Result := Format('FreeAndNil(%s);', [AField]);
  end
  else
  begin
    Result := AField + '.Free;';
  end;
end;

class function TPascalDestructors.DestructorEdits(ATree: TSyntaxTree; const AText, AClassName: string; ALine: Integer;
  const AStatements: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean;
var
  mDecl: TSyntaxNode;
  mPlace: TDestructorPlace;
  mLines: TArray<string>;
  mLineBreak: string;
begin
  AEdits := nil;
  mDecl := nil;
  if (ATree <> nil) and (ATree.Root <> nil) and (Length(AStatements) > 0) then
  begin
    mDecl := FindClassDecl(ATree, AClassName, ALine);
  end;
  if mDecl = nil then
  begin
    Exit(False);
  end;
  mPlace := PlaceOf(ATree, AText, mDecl);
  if mPlace.Body = nil then
  begin
    Exit(NewDestructor(AText, mDecl, mPlace, AStatements, AEdits));
  end;
  mLines := TTextLines.SplitLines(AText, mLineBreak);
  AEdits := [BodyEdit(mLines, mPlace.Body, AStatements, mLineBreak)];
  Result := True;
end;

class function TPascalDestructors.ClassMethods(ATree: TSyntaxTree; const AClassName: string): TArray<TSyntaxNode>;
begin
  Result := MethodBodies(ATree, AClassName);
end;

class function TPascalDestructors.IsConstructor(const AText: string; ADecl: TSyntaxNode): Boolean;
begin
  Result := IsConstructorDecl(AText, ADecl);
end;

/// <summary>Beginnt der Kopf mit "class constructor" bzw. "class destructor" (AKind)?</summary>
function IsClassStructor(const AText: string; AHeader: TSyntaxNode; const AKind: string): Boolean;
var
  mText: string;
begin
  Result := False;
  if AHeader = nil then
  begin
    Exit;
  end;
  mText := TTextLines.CollapseSpace(NodeText(AText, AHeader));
  Result := StartsWithWord(mText, 'class') and StartsWithWord(Trim(Copy(mText, Length('class') + 1, MaxInt)), AKind);
end;

/// <summary>Deklaration des class constructor in der Klasse; nil ohne.</summary>
function ClassConstructorDecl(const AText: string; AClassNode: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AClassNode.ChildCount - 1 do
  begin
    if (AClassNode[mIndex].Kind = TSyntaxKind.RoutineHeader) and
      IsClassStructor(AText, AClassNode[mIndex], 'constructor') then
    begin
      Result := AClassNode[mIndex];
    end;
  end;
end;

/// <summary>Rümpfe des class destructor und des letzten class constructor; nil ohne.</summary>
procedure ClassStructorBodies(ATree: TSyntaxTree; const AText: string; AClassDecl: TSyntaxNode;
  out ABody, ALastConstructor: TSyntaxNode);
var
  mDecl: TSyntaxNode;
begin
  ABody := nil;
  ALastConstructor := nil;
  for mDecl in MethodBodies(ATree, AClassDecl.Name) do
  begin
    if IsClassStructor(AText, HeaderOf(mDecl), 'destructor') then
    begin
      ABody := mDecl;
    end
    else if IsClassStructor(AText, HeaderOf(mDecl), 'constructor') then
    begin
      ALastConstructor := mDecl;
    end;
  end;
end;

class function TPascalDestructors.ClassDestructorEdits(ATree: TSyntaxTree; const AText: string; AClassDecl: TSyntaxNode;
  const AStatements: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean;
var
  mDeclaration, mBody, mLast: TSyntaxNode;
  mLines: TArray<string>;
  mLineBreak, mHeader: string;
begin
  AEdits := nil;
  if (ATree = nil) or (AClassDecl = nil) or (Length(AStatements) = 0) or
    (AClassDecl.FindChild(TSyntaxKind.ClassType) = nil) then
  begin
    Exit(False);
  end;
  mLines := TTextLines.SplitLines(AText, mLineBreak);
  ClassStructorBodies(ATree, AText, AClassDecl, mBody, mLast);
  if mBody <> nil then
  begin
    AEdits := [BodyEdit(mLines, mBody, AStatements, mLineBreak)];
    Exit(True);
  end;
  mDeclaration := ClassConstructorDecl(AText, AClassDecl.FindChild(TSyntaxKind.ClassType));
  // Deklaration in eigener Zeile hinter dem class constructor, gleich eingerückt.
  Result := (mDeclaration <> nil) and (mLast <> nil) and (mDeclaration.EndPos.Line <= High(mLines));
  if Result then
  begin
    mHeader := Format('class destructor %s.Destroy;', [Qualifier(AText, mLast, AClassDecl.Name)]);
    AEdits := [AppendLine(mLines, mDeclaration.EndPos.Line, mLineBreak +
      TTextLines.IndentOf(mLines[mDeclaration.StartPos.Line]) + 'class destructor Destroy;'),
      InsertAt(mLast.EndPos, mLineBreak + mLineBreak + RoutineText(StringOfChar(' ', mLast.StartPos.Character),
      mHeader, AStatements, mLineBreak))];
  end;
end;

end.
