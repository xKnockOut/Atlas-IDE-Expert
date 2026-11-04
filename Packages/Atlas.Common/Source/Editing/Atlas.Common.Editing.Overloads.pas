unit Atlas.Common.Editing.Overloads;

// Überladung anlegen (#674), ohne Index und Protokoll:
//   - Ziel: eine Routine mit Rumpf in der Unit, Methode einer Klasse oder
//     eines Records oder freie Routine; der Cursor steht auf ihrem Kopf in
//     der Deklaration oder in der Implementierung. Überladungen gleichen
//     Namens unterscheidet Atlas an den Parametertypen.
//   - Kopie: Deklaration und Rumpf direkt hinter das Original, beide mit
//     overload. Platzhalter: erst die Parameterliste der Kopie (in Deklaration
//     und Implementierung verknüpft), dann der Rumpf.
//   - Weiterleitung: die neue Überladung ohne den letzten Parameter ruft die
//     bestehende auf und gibt für ihn den Standardwert seines Typs mit
//     (Platzhalter); bei Funktionen mit "Result := ".
//   - virtual, dynamic, override, abstract, reintroduce, message und final
//     übernimmt die neue Überladung nicht. Ist das Original ein override,
//     kommt ein Hinweis: Die neue Überladung ist nicht virtuell.
//   - Der ///-Kommentar wird mitkopiert; bei der Weiterleitung entfällt der
//     <param> des weggelassenen Parameters.
//   - Die Kopie steht in Deklaration und Implementierung direkt hinter dem
//     Original und folgt damit der Deklarationsreihenfolge (#660).
// Das Zusammenführen von Überladungen über Standardwerte gibt es bewusst
// nicht: Atlas legt Überladungen an, keine Standardparameter.
// Nicht für Destruktoren, generische Routinen, abstrakte Methoden und
// Routinen ohne Rumpf in der Unit.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.ChangeSignature;

type
{$SCOPEDENUMS ON}
  TOverloadKind = (Copy, Forward);
{$SCOPEDENUMS OFF}

  /// <summary>Standardwert für einen weggelassenen Parameter vom Typ ATypeName, dessen Typ an ATypeOffset im Text
  /// steht; '' = eingebaute Regel bzw. Default(Typ).</summary>
  TOverloadDefaultFunc = reference to function(const ATypeName: string; ATypeOffset: Integer): string;

  /// <summary>Platzhalter im Text nach den Änderungen; Nummer 0 = Endposition.</summary>
  TOverloadPlaceholder = record
    Number: Integer;
    Range: TTextRange;
  end;

  /// <summary>Routine, zu der eine Überladung entstehen kann; Token-Indizes in der Tokenliste der Datei.</summary>
  TOverloadTarget = record
    Name: string;
    /// <summary>Klasse bzw. Record; '' bei freien Routinen.</summary>
    Container: string;
    /// <summary>Kopf der Deklaration; bei Routinen nur in implementation derselbe wie Body.</summary>
    Decl: TSignatureHeader;
    Body: TSignatureHeader;
    /// <summary>Eigene Deklaration (in der Klasse bzw. im interface).</summary>
    HasDecl: Boolean;
    /// <summary>";" hinter dem end der Implementierung.</summary>
    BodyLast: Integer;
    /// <summary>begin bzw. end des Hauptblocks.</summary>
    BlockBegin: Integer;
    BlockEnd: Integer;
    /// <summary>Anfang des Typs des letzten Parameters (Offset); -1 ohne.</summary>
    LastTypeOffset: Integer;
    /// <summary>Warum es nicht geht; '' = geht.</summary>
    CopyReason: string;
    ForwardReason: string;
    /// <summary>Hinweis nach dem Anlegen ('' ohne).</summary>
    Note: string;
    function Title(AKind: TOverloadKind): string;
    function Reason(AKind: TOverloadKind): string;
  end;

  /// <summary>Art der neuen Überladung; DefaultOf liefert den Standardwert des weggelassenen Parameters
  /// (Namensauflösung, nil = eingebaute Regel).</summary>
  TOverloadRequest = record
    Kind: TOverloadKind;
    DefaultOf: TOverloadDefaultFunc;
    class function Create(AKind: TOverloadKind; const ADefaultOf: TOverloadDefaultFunc): TOverloadRequest; static;
  end;

  TOverloadResult = record
    Edits: TArray<TTextEdit>;
    /// <summary>In Textreihenfolge, zuletzt die Endposition.</summary>
    Placeholders: TArray<TOverloadPlaceholder>;
    Warnings: TArray<string>;
    /// <summary>Text nach den Änderungen.</summary>
    NewText: string;
  end;

  TOverloads = class
  public const
    CopyTitle = 'Überladung anlegen (Kopie)';
    ForwardTitle = 'Überladung anlegen (als Weiterleitung)';
    DestructorReason = 'Destruktoren überlädt Atlas nicht.';
    GenericReason = 'Generische Routinen überlädt Atlas nicht.';
    NoParameterReason = 'Ohne Parameter gibt es keinen, der in der Weiterleitung wegfallen kann.';
    VarParameterReason = 'Der letzte Parameter %s ist var bzw. out; die Weiterleitung hätte keinen Wert dafür.';
    ExistsReason = 'Die Überladung %s(%s) gibt es schon.';
    OverrideNote = 'Die neue Überladung von %s ist nicht virtuell, weil das Original eine Methode des Vorfahren ' +
      'überschreibt. In den Vorfahr bringt sie „Mitglied in Vorfahr verschieben“.';
  public
    /// <summary>Routine, auf deren Kopf (Deklaration oder Implementierung) APosition steht.</summary>
    class function Target(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      out ATarget: TOverloadTarget): Boolean; static;
    /// <summary>Änderungen für die neue Überladung; False mit AReason, wenn es nicht geht.</summary>
    class function Build(const AText: string; ATree: TSyntaxTree; const ATarget: TOverloadTarget;
      AKind: TOverloadKind; out AResult: TOverloadResult; out AReason: string): Boolean; overload; static;
    /// <summary>Wie oben mit Art und Standardwert aus ARequest.</summary>
    class function Build(const AText: string; ATree: TSyntaxTree; const ATarget: TOverloadTarget;
      const ARequest: TOverloadRequest; out AResult: TOverloadResult; out AReason: string): Boolean; overload;
      static;
    /// <summary>Standardwert eingebauter Typen (0, '', #0, False, nil, []); '' bei anderen.</summary>
    class function DefaultValue(const ATypeName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineParts,
  Atlas.Text.Lines;

type
  /// <summary>Platzhalter in einer Einfügung, Offsets ab ihrem Anfang.</summary>
  TInsertField = record
    Number: Integer;
    Start: Integer;
    Length: Integer;
  end;

  /// <summary>Einfügung an einem Offset des alten Texts.</summary>
  TInsert = record
    Offset: Integer;
    Text: string;
    Fields: TArray<TInsertField>;
    /// <summary>Reihenfolge bei gleichem Offset.</summary>
    Sequence: Integer;
  end;

  /// <summary>Sammelt Einfügungen und den Text, der gerade entsteht.</summary>
  TInsertBuilder = record
    Text: string;
    Fields: TArray<TInsertField>;
    procedure Add(const AText: string); overload;
    /// <summary>Text als Platzhalter ANumber.</summary>
    procedure Add(const AText: string; ANumber: Integer); overload;
  end;

procedure TInsertBuilder.Add(const AText: string);
begin
  Text := Text + AText;
end;

procedure TInsertBuilder.Add(const AText: string; ANumber: Integer);
var
  Field: TInsertField;
begin
  Field.Number := ANumber;
  Field.Start := System.Length(Text);
  Field.Length := System.Length(AText);
  Fields := Fields + [Field];
  Text := Text + AText;
end;

function MakeInsert(AOffset: Integer; const ABuilder: TInsertBuilder): TInsert;
begin
  Result.Offset := AOffset;
  Result.Text := ABuilder.Text;
  Result.Fields := ABuilder.Fields;
  Result.Sequence := 0;
end;

function PlainInsert(AOffset: Integer; const AText: string): TInsert;
begin
  Result.Offset := AOffset;
  Result.Text := AText;
  Result.Fields := nil;
  Result.Sequence := 0;
end;

{ TOverloadTarget }

function TOverloadTarget.Title(AKind: TOverloadKind): string;
begin
  if AKind = TOverloadKind.Forward then
  begin
    Result := TOverloads.ForwardTitle;
  end
  else
  begin
    Result := TOverloads.CopyTitle;
  end;
end;

function TOverloadTarget.Reason(AKind: TOverloadKind): string;
begin
  if AKind = TOverloadKind.Forward then
  begin
    Result := ForwardReason;
  end
  else
  begin
    Result := CopyReason;
  end;
end;

{ Hilfen }

function TokenEnd(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := ATokens[AIndex].Offset + Length(ATokens[AIndex].Text);
end;

/// <summary>Kurzname eines Kopfs: "TFoo.Bar" ergibt "Bar".</summary>
function ShortName(const AName: string): string;
begin
  Result := AName;
  if LastDelimiter('.', Result) > 0 then
  begin
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
end;

/// <summary>Token des Namens im Kopf AHeader: das erste Bezeichner-Token mit dem Kurznamen.</summary>
function NameToken(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): Integer;
var
  Index: Integer;
  Name: string;
begin
  Name := ShortName(AHeader.Name);
  for Index := 0 to High(ATokens) do
  begin
    if ATokens[Index].Offset >= AHeader.EndOffset then
    begin
      Break;
    end;
    if (ATokens[Index].Offset >= AHeader.StartOffset) and (ATokens[Index].Kind = TPascalTokenKind.Identifier) and
      SameText(ATokens[Index].Text, Name) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function ReadNode(const AText: string; ATree: TSyntaxTree; AHeader: TSyntaxNode;
  out ASignature: TSignatureHeader): Boolean;
begin
  Result := (AHeader <> nil) and TChangeSignature.ReadHeader(AText, ATree.Tokens, NameToken(ATree.Tokens, AHeader),
    ASignature);
end;

function SameTypes(const A, B: TArray<string>): Boolean;
var
  Index: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
  begin
    for Index := 0 to High(A) do
    begin
      if not SameText(StringReplace(A[Index], ' ', '', [rfReplaceAll]),
        StringReplace(B[Index], ' ', '', [rfReplaceAll])) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

/// <summary>Klasse bzw. Record AName der Datei; nil ohne.</summary>
function FindType(ARoot: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Index: Integer;
    begin
      Result := Found = nil;
      if Result and (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, AName) then
      begin
        for Index := 0 to ANode.ChildCount - 1 do
        begin
          if ANode[Index].Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType] then
          begin
            Found := ANode[Index];
          end;
        end;
      end;
    end);
  Result := Found;
end;

/// <summary>Köpfe der Routinen namens AName direkt in ASection; nil ohne Abschnitt.</summary>
function SectionHeaders(ATree: TSyntaxTree; const AText, AName: string;
  ASection: TSyntaxNode): TArray<TSignatureHeader>;
var
  mIndex: Integer;
  mHeader: TSignatureHeader;
begin
  Result := nil;
  if ASection = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    if (ASection[mIndex].Kind = TSyntaxKind.RoutineDecl) and SameText(ASection[mIndex].Name, AName) and
      ReadNode(AText, ATree, TRoutineParts.HeaderOf(ASection[mIndex]), mHeader) then
    begin
      Result := Result + [mHeader];
    end;
  end;
end;

/// <summary>Köpfe der Methoden namens AName in der Klasse bzw. dem Record AType.</summary>
function TypeHeaders(ATree: TSyntaxTree; const AText, AName: string; AType: TSyntaxNode): TArray<TSignatureHeader>;
var
  mIndex: Integer;
  mHeader: TSignatureHeader;
begin
  Result := nil;
  for mIndex := 0 to AType.ChildCount - 1 do
  begin
    if (AType[mIndex].Kind = TSyntaxKind.RoutineHeader) and SameText(AType[mIndex].Name, AName) and
      ReadNode(AText, ATree, AType[mIndex], mHeader) then
    begin
      Result := Result + [mHeader];
    end;
  end;
end;

/// <summary>Köpfe aller Routinen namens AName: in der Klasse AType bzw. auf Unit-Ebene (beide Teile).</summary>
function Overloads(ATree: TSyntaxTree; const AText, AName: string; AType: TSyntaxNode): TArray<TSignatureHeader>;
var
  mKind: TSyntaxKind;
begin
  if AType <> nil then
  begin
    Exit(TypeHeaders(ATree, AText, AName, AType));
  end;
  Result := nil;
  for mKind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] do
  begin
    Result := Result + SectionHeaders(ATree, AText, AName, ATree.Root.FindChild(mKind));
  end;
end;

/// <summary>Implementierung zur Deklaration ADecl (Name AQualified) im implementation-Teil; nil ohne.</summary>
function FindBody(ATree: TSyntaxTree; const AText, AQualified: string; const ADecl: TSignatureHeader;
  out ABody: TSignatureHeader): TSyntaxNode;
var
  Section: TSyntaxNode;
  Index, Count: Integer;
  Header: TSignatureHeader;
  Single: TSyntaxNode;
  SingleHeader: TSignatureHeader;
begin
  Result := nil;
  ABody := Default(TSignatureHeader);
  Section := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Section = nil then
  begin
    Exit;
  end;
  Count := 0;
  Single := nil;
  SingleHeader := Default(TSignatureHeader);
  for Index := 0 to Section.ChildCount - 1 do
  begin
    if (Section[Index].Kind = TSyntaxKind.RoutineDecl) and SameText(Section[Index].Name, AQualified) and
      (Section[Index].FindChild(TSyntaxKind.Block) <> nil) and
      ReadNode(AText, ATree, TRoutineParts.HeaderOf(Section[Index]), Header) then
    begin
      Inc(Count);
      Single := Section[Index];
      SingleHeader := Header;
      if SameTypes(Header.ParamTypes, ADecl.ParamTypes) then
      begin
        ABody := Header;
        Exit(Section[Index]);
      end;
    end;
  end;
  // Ohne Überladung darf die Implementierung die Parameter weglassen.
  if (Count = 1) and (SingleHeader.OpenToken < 0) then
  begin
    ABody := SingleHeader;
    Result := Single;
  end;
end;

/// <summary>Deklaration zur Implementierung ABody: in der Klasse AType bzw. im interface; nil ohne.</summary>
function FindDecl(ATree: TSyntaxTree; const AText: string; AType: TSyntaxNode; const AName: string;
  const ABody: TSignatureHeader; out ADecl: TSignatureHeader): Boolean;
var
  mCandidates: TArray<TSignatureHeader>;
  mCandidate: TSignatureHeader;
begin
  ADecl := Default(TSignatureHeader);
  if AType <> nil then
  begin
    mCandidates := Overloads(ATree, AText, AName, AType);
  end
  else
  begin
    mCandidates := SectionHeaders(ATree, AText, AName, ATree.Root.FindChild(TSyntaxKind.InterfaceSection));
  end;
  for mCandidate in mCandidates do
  begin
    if SameTypes(mCandidate.ParamTypes, ABody.ParamTypes) then
    begin
      ADecl := mCandidate;
      Exit(True);
    end;
  end;
  Result := (Length(mCandidates) = 1) and (ABody.OpenToken < 0);
  if Result then
  begin
    ADecl := mCandidates[0];
  end;
end;

/// <summary>Anfang des Typs des letzten Parameters im Kopf AHeader; -1 ohne.</summary>
function LastTypeOffset(AHeader: TSyntaxNode): Integer;
var
  Parameters, Parameter: TSyntaxNode;
begin
  Result := -1;
  if AHeader = nil then
  begin
    Exit;
  end;
  Parameters := AHeader.FindChild(TSyntaxKind.Parameters);
  if (Parameters = nil) or (Parameters.ChildCount = 0) then
  begin
    Exit;
  end;
  Parameter := Parameters[Parameters.ChildCount - 1];
  if (Parameter.ChildCount > 0) and (Parameter[Parameter.ChildCount - 1].Kind = TSyntaxKind.TypeReference) then
  begin
    Result := Parameter[Parameter.ChildCount - 1].StartOffset;
  end
  else if Parameter.ChildCount > 0 then
  begin
    Result := Parameter[0].StartOffset;
  end;
end;

/// <summary>Innerster Kopf (RoutineHeader), der AOffset enthält; nil ohne.</summary>
function HeaderNodeAt(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := TRoutineParts.Encloses(ANode, AOffset);
      if Result and (ANode.Kind = TSyntaxKind.RoutineHeader) then
      begin
        Found := ANode;
      end;
    end);
  Result := Found;
end;

function IsModifier(const AModifier, AWord: string): Boolean;
var
  Part: string;
begin
  for Part in AModifier.Split([' ']) do
  begin
    if SameText(Part, AWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Innerster Kopf einer Methode in einer Klasse bzw. einem Record, der AOffset enthält; nil ohne.
/// </summary>
function MemberHeaderAt(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := TRoutineParts.Encloses(ANode, AOffset);
      if Result and (ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode.Parent <> nil) and
        (ANode.Parent.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType]) then
      begin
        Found := ANode;
      end;
    end);
  Result := Found;
end;

type
  /// <summary>Liest die Routine zu TOverloads.Target Schritt für Schritt.</summary>
  TTargetReader = record
    Text: string;
    Tree: TSyntaxTree;
    Tokens: TArray<TPascalToken>;
    DeclHeader: TSyntaxNode;
    BodyNode: TSyntaxNode;
    TypeNode: TSyntaxNode;
    Target: TOverloadTarget;
    /// <summary>Routine bzw. Methode, auf deren Kopf AOffset steht.</summary>
    function Locate(AOffset: Integer): Boolean;
    function LocateRoutine(ARoutine: TSyntaxNode): Boolean;
    function LocateMember(AOffset: Integer): Boolean;
    function ReadHeaders: Boolean;
    function ReadFromDecl: Boolean;
    function ReadFromBody: Boolean;
    /// <summary>Klasse bzw. Record aus dem Namen der Implementierung ("TFoo.Bar").</summary>
    function ResolveContainer: Boolean;
    function ReadDeclOfBody: Boolean;
    function ReadBlock: Boolean;
    function IsGeneric: Boolean;
    function ForwardIssue: string;
    procedure SetReasons;
  end;

function TTargetReader.Locate(AOffset: Integer): Boolean;
var
  mRoutine: TSyntaxNode;
begin
  mRoutine := TRoutineParts.RoutineWithHeaderAt(Tree, AOffset);
  if mRoutine <> nil then
  begin
    Result := LocateRoutine(mRoutine);
  end
  else
  begin
    Result := LocateMember(AOffset);
  end;
end;

function TTargetReader.LocateRoutine(ARoutine: TSyntaxNode): Boolean;
begin
  Result := (ARoutine.Parent <> nil) and (ARoutine.Parent.Kind in [TSyntaxKind.InterfaceSection,
    TSyntaxKind.ImplementationSection]);
  if not Result then
  begin
    Exit;
  end;
  if ARoutine.FindChild(TSyntaxKind.Block) <> nil then
  begin
    BodyNode := ARoutine;
  end
  else if ARoutine.Parent.Kind = TSyntaxKind.InterfaceSection then
  begin
    DeclHeader := TRoutineParts.HeaderOf(ARoutine);
  end
  else
  begin
    Result := False;
  end;
end;

function TTargetReader.LocateMember(AOffset: Integer): Boolean;
var
  mFound: TSyntaxNode;
begin
  // Kopf in einer Klasse bzw. einem Record.
  mFound := MemberHeaderAt(Tree, AOffset);
  Result := (mFound <> nil) and (mFound.Parent.Parent <> nil);
  if Result then
  begin
    DeclHeader := mFound;
    TypeNode := mFound.Parent;
    Target.Container := mFound.Parent.Parent.Name;
  end;
end;

function TTargetReader.ReadHeaders: Boolean;
begin
  if DeclHeader <> nil then
  begin
    Result := ReadFromDecl;
  end
  else
  begin
    Result := ReadFromBody;
  end;
end;

function TTargetReader.ReadFromDecl: Boolean;
var
  mQualified: string;
begin
  Result := ReadNode(Text, Tree, DeclHeader, Target.Decl);
  if not Result then
  begin
    Exit;
  end;
  Target.HasDecl := True;
  Target.Name := ShortName(Target.Decl.QualifiedName);
  mQualified := Target.Name;
  if Target.Container <> '' then
  begin
    mQualified := Target.Container + '.' + Target.Name;
  end;
  BodyNode := FindBody(Tree, Text, mQualified, Target.Decl, Target.Body);
  Result := BodyNode <> nil;
  if Result then
  begin
    Target.LastTypeOffset := LastTypeOffset(DeclHeader);
  end;
end;

function TTargetReader.ResolveContainer: Boolean;
var
  mQualified: string;
begin
  Result := True;
  mQualified := Target.Body.QualifiedName;
  if Pos('.', mQualified) = 0 then
  begin
    Exit;
  end;
  Target.Container := Copy(mQualified, 1, LastDelimiter('.', mQualified) - 1);
  if Pos('.', Target.Container) > 0 then
  begin
    Target.Container := ShortName(Target.Container);
  end;
  TypeNode := FindType(Tree.Root, Target.Container);
  Result := TypeNode <> nil;
end;

function TTargetReader.ReadDeclOfBody: Boolean;
var
  mHeader: TSignatureHeader;
begin
  Result := True;
  if FindDecl(Tree, Text, TypeNode, Target.Name, Target.Body, mHeader) then
  begin
    Target.Decl := mHeader;
    Target.HasDecl := True;
  end
  else if Target.Container <> '' then
  begin
    Result := False;
  end
  else
  begin
    Target.Decl := Target.Body;
  end;
end;

function TTargetReader.ReadFromBody: Boolean;
begin
  Result := ReadNode(Text, Tree, TRoutineParts.HeaderOf(BodyNode), Target.Body);
  if not Result then
  begin
    Exit;
  end;
  Target.Name := ShortName(Target.Body.QualifiedName);
  Result := ResolveContainer and ReadDeclOfBody;
  // Typ des letzten Parameters: aus der Deklaration, sonst aus dem Kopf der Implementierung.
  if Result and Target.HasDecl then
  begin
    Target.LastTypeOffset := LastTypeOffset(HeaderNodeAt(Tree, Tokens[Target.Decl.NameToken].Offset));
  end
  else if Result then
  begin
    Target.LastTypeOffset := LastTypeOffset(TRoutineParts.HeaderOf(BodyNode));
  end;
end;

function TTargetReader.ReadBlock: Boolean;
var
  mBlock: TSyntaxNode;
begin
  mBlock := BodyNode.FindChild(TSyntaxKind.Block);
  Result := mBlock <> nil;
  if not Result then
  begin
    Exit;
  end;
  Target.BlockBegin := TRoutineBody.TokenAt(Tokens, mBlock.StartOffset);
  Target.BodyLast := TChangeSignature.BodyEnd(Tree, Target.Body);
  Result := (Target.BlockBegin <= High(Tokens)) and Tokens[Target.BlockBegin].IsKeyword('begin') and
    (Target.BodyLast >= 0);
  if not Result then
  begin
    Exit;
  end;
  Target.BlockEnd := Target.BodyLast;
  while (Target.BlockEnd > Target.BlockBegin) and not Tokens[Target.BlockEnd].IsKeyword('end') do
  begin
    Dec(Target.BlockEnd);
  end;
  Result := Target.BlockEnd > Target.BlockBegin;
end;

function TTargetReader.IsGeneric: Boolean;
begin
  Result := (Target.Decl.NameToken < High(Tokens)) and Tokens[Target.Decl.NameToken + 1].IsSymbol('<');
end;

/// <summary>Warum die Weiterleitung beim letzten Parameter nicht geht; '' = geht.</summary>
function TTargetReader.ForwardIssue: string;
var
  mLast: TSignatureParameter;
  mWanted: TArray<string>;
  mHeader: TSignatureHeader;
begin
  mLast := Target.Decl.Parameters[High(Target.Decl.Parameters)];
  if IsModifier(mLast.Modifier, 'var') or IsModifier(mLast.Modifier, 'out') or (mLast.TypeName = '') then
  begin
    Exit(Format(TOverloads.VarParameterReason, [mLast.Name]));
  end;
  Result := '';
  mWanted := Copy(Target.Decl.ParamTypes, 0, Length(Target.Decl.Parameters) - 1);
  for mHeader in Overloads(Tree, Text, Target.Name, TypeNode) do
  begin
    if SameTypes(mHeader.ParamTypes, mWanted) then
    begin
      Exit(Format(TOverloads.ExistsReason, [Target.Name, string.Join(', ', mWanted)]));
    end;
  end;
end;

procedure TTargetReader.SetReasons;
begin
  if Target.Decl.Keyword = 'destructor' then
  begin
    Target.CopyReason := TOverloads.DestructorReason;
    Target.ForwardReason := TOverloads.DestructorReason;
  end
  else if IsGeneric then
  begin
    Target.CopyReason := TOverloads.GenericReason;
    Target.ForwardReason := TOverloads.GenericReason;
  end
  else if Length(Target.Decl.Parameters) = 0 then
  begin
    Target.ForwardReason := TOverloads.NoParameterReason;
  end
  else
  begin
    Target.ForwardReason := ForwardIssue;
  end;
  if Target.Decl.HasDirective('override') then
  begin
    Target.Note := Format(TOverloads.OverrideNote, [Target.Name]);
  end;
end;

{ TOverloads }

class function TOverloads.Target(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  out ATarget: TOverloadTarget): Boolean;
var
  mReader: TTargetReader;
  mLines: TLineTable;
begin
  ATarget := Default(TOverloadTarget);
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit(False);
  end;
  mReader := Default(TTargetReader);
  mReader.Text := AText;
  mReader.Tree := ATree;
  mReader.Tokens := ATree.Tokens;
  mLines := TLineTable.Build(AText);
  Result := mReader.Locate(mLines.OffsetAt(APosition)) and mReader.ReadHeaders and mReader.ReadBlock;
  if Result then
  begin
    mReader.SetReasons;
  end;
  ATarget := mReader.Target;
end;

class function TOverloads.DefaultValue(const ATypeName: string): string;
const
  Numbers: array[0..27] of string = ('integer', 'cardinal', 'int64', 'uint64', 'byte', 'word', 'shortint',
    'smallint', 'longint', 'longword', 'nativeint', 'nativeuint', 'int8', 'int16', 'int32', 'uint8', 'uint16',
    'uint32', 'single', 'double', 'extended', 'real', 'currency', 'comp', 'tdatetime', 'tdate', 'ttime', 'fixedint');
  Strings: array[0..6] of string = ('string', 'ansistring', 'unicodestring', 'widestring', 'rawbytestring',
    'utf8string', 'shortstring');
  Chars: array[0..2] of string = ('char', 'ansichar', 'widechar');
  Booleans: array[0..3] of string = ('boolean', 'bytebool', 'wordbool', 'longbool');
  Pointers: array[0..8] of string = ('pointer', 'tobject', 'tclass', 'iinterface', 'iunknown', 'pchar', 'pansichar',
    'pwidechar', 'tprocedure');
var
  Name: string;
begin
  Name := LowerCase(Trim(ATypeName));
  if StartsText('system.', Name) then
  begin
    Name := Copy(Name, Length('system.') + 1, MaxInt);
  end;
  if StartsText('array of ', Name) then
  begin
    Result := '[]';
  end
  else if IndexText(Name, Numbers) >= 0 then
  begin
    Result := '0';
  end
  else if IndexText(Name, Strings) >= 0 then
  begin
    Result := '''''';
  end
  else if IndexText(Name, Chars) >= 0 then
  begin
    Result := '#0';
  end
  else if IndexText(Name, Booleans) >= 0 then
  begin
    Result := 'False';
  end
  else if IndexText(Name, Pointers) >= 0 then
  begin
    Result := 'nil';
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Der ///-Kommentar über Zeile ALine (Attribute dazwischen übersprungen), ohne Einrückung; bei
/// ADropped ohne den &lt;param&gt; dieses Namens.</summary>
function DocLines(const ALines: TArray<string>; ALine: Integer; const ADropped: string): TArray<string>;
var
  Line, First: Integer;
  Inside: Boolean;
  Text: string;
begin
  Result := nil;
  Line := ALine - 1;
  while (Line >= 0) and StartsStr('[', Trim(ALines[Line])) do
  begin
    Dec(Line);
  end;
  First := Line + 1;
  while (Line >= 0) and StartsStr('///', Trim(ALines[Line])) do
  begin
    First := Line;
    Dec(Line);
  end;
  Inside := False;
  for Line := First to ALine - 1 do
  begin
    Text := Trim(ALines[Line]);
    if not StartsStr('///', Text) then
    begin
      Continue;
    end;
    if (ADropped <> '') and not Inside and ContainsText(Text, '<param name="' + ADropped + '"') then
    begin
      Inside := not ContainsText(Text, '</param>');
      Continue;
    end;
    if Inside then
    begin
      Inside := not ContainsText(Text, '</param>');
      Continue;
    end;
    Result := Result + [Text];
  end;
end;

function DocBlock(const ADoc: TArray<string>; const AIndent, ALineBreak: string): string;
var
  Line: string;
begin
  Result := '';
  for Line in ADoc do
  begin
    Result := Result + AIndent + Line + ALineBreak;
  end;
end;

/// <summary>Text der Parameterliste ohne Klammern: wie im Original, mit Standardwerten ohne sie.</summary>
function ParameterText(const AText: string; const ATokens: TArray<TPascalToken>;
  const AHeader: TSignatureHeader): string;
var
  Parameter: TSignatureParameter;
  HasDefault: Boolean;
begin
  HasDefault := False;
  for Parameter in AHeader.Parameters do
  begin
    if Parameter.DefaultValue <> '' then
    begin
      HasDefault := True;
    end;
  end;
  if HasDefault or (AHeader.OpenToken < 0) then
  begin
    Result := TChangeSignature.ParameterList(AHeader.Parameters, False);
    if Result <> '' then
    begin
      Result := Copy(Result, 2, Length(Result) - 2);
    end;
  end
  else
  begin
    Result := Copy(AText, TokenEnd(ATokens, AHeader.OpenToken) + 1,
      ATokens[AHeader.CloseToken].Offset - TokenEnd(ATokens, AHeader.OpenToken));
  end;
end;

/// <summary>Kopf bis einschließlich Name ("class function TFoo.Bar") wie im Text.</summary>
function HeadText(const AText: string; const ATokens: TArray<TPascalToken>; const AHeader: TSignatureHeader): string;
begin
  Result := Copy(AText, ATokens[AHeader.StartToken].Offset + 1,
    TokenEnd(ATokens, AHeader.NameToken) - ATokens[AHeader.StartToken].Offset);
end;

/// <summary>Hinter den Klammern bis einschließlich ";" (": string;") wie im Text.</summary>
function TailText(const AText: string; const ATokens: TArray<TPascalToken>; const AHeader: TSignatureHeader): string;
var
  From: Integer;
begin
  if AHeader.CloseToken >= 0 then
  begin
    From := TokenEnd(ATokens, AHeader.CloseToken);
  end
  else
  begin
    From := TokenEnd(ATokens, AHeader.NameToken);
  end;
  Result := Copy(AText, From + 1, TokenEnd(ATokens, AHeader.EndToken) - From);
end;

/// <summary>Kopf der neuen Überladung mit der Parameterliste AParameters als Platzhalter 1.</summary>
procedure AddHead(var ABuilder: TInsertBuilder; const AText: string; const ATokens: TArray<TPascalToken>;
  const AHeader: TSignatureHeader; const AParameters: string; ADirectives: Boolean);
begin
  ABuilder.Add(HeadText(AText, ATokens, AHeader) + '(');
  ABuilder.Add(AParameters, 1);
  ABuilder.Add(')' + TailText(AText, ATokens, AHeader));
  if ADirectives then
  begin
    ABuilder.Add(TChangeSignature.OverloadDirectives(AHeader, False));
  end;
end;

/// <summary>" overload;" für das Original: hinter dem Kopf, ohne weitere Direktiven in derselben Einfügung wie
/// die Kopie (feste Reihenfolge).</summary>
function NeedsOverload(const AHeader: TSignatureHeader): Boolean;
begin
  Result := not AHeader.HasDirective('overload');
end;

function MergeInserts(const AInserts: TArray<TInsert>): TArray<TInsert>;
var
  Index: Integer;
begin
  Result := Copy(AInserts);
  for Index := 0 to High(Result) do
  begin
    Result[Index].Sequence := Index;
  end;
  TArray.Sort<TInsert>(Result, TComparer<TInsert>.Construct(
    function(const A, B: TInsert): Integer
    begin
      if A.Offset <> B.Offset then
      begin
        Result := A.Offset - B.Offset;
      end
      else
      begin
        Result := A.Sequence - B.Sequence;
      end;
    end));
end;

/// <summary>Platzhalter AField einer Einfügung, die im neuen Text an AOffset steht.</summary>
function PlaceholderOf(const ALines: TLineTable; AOffset: Integer; const AField: TInsertField): TOverloadPlaceholder;
begin
  Result.Number := AField.Number;
  Result.Range := TTextRange.Create(ALines.PositionAt(AOffset + AField.Start),
    ALines.PositionAt(AOffset + AField.Start + AField.Length));
end;

type
  /// <summary>Baut die Einfügungen für TOverloads.Build.</summary>
  TOverloadWriter = record
    Text: string;
    Tokens: TArray<TPascalToken>;
    Target: TOverloadTarget;
    Request: TOverloadRequest;
    LineBreak: string;
    DeclIndent: string;
    BodyIndent: string;
    /// <summary>Parameterliste der neuen Überladung ohne Klammern.</summary>
    Parameters: string;
    /// <summary>Weiterleitung: die Parameter ohne den letzten.</summary>
    Kept: TArray<TSignatureParameter>;
    Doc: TArray<string>;
    Inserts: TArray<TInsert>;
    procedure Prepare;
    /// <summary>Deklaration: Kopie hinter dem Original, das selbst overload bekommt.</summary>
    procedure AddDeclaration;
    /// <summary>Implementierung hinter der des Originals.</summary>
    procedure AddBody;
    procedure AddCopyBody(var ABody: TInsertBuilder);
    procedure AddForwardBody(var ABody: TInsertBuilder);
    function ForwardValue: string;
    /// <summary>Text danach, Platzhalter darin und die Änderungen.</summary>
    function Outcome: TOverloadResult;
  end;

procedure TOverloadWriter.Prepare;
var
  mLines: TArray<string>;
  mDropped: string;
begin
  mLines := TTextLines.SplitLines(Text);
  LineBreak := TTextLines.LineBreakOf(Text);
  DeclIndent := TTextLines.IndentOf(mLines[Tokens[Target.Decl.StartToken].StartPos.Line]);
  BodyIndent := TTextLines.IndentOf(mLines[Tokens[Target.Body.StartToken].StartPos.Line]);
  Inserts := nil;
  mDropped := '';
  if Request.Kind = TOverloadKind.Forward then
  begin
    Kept := Copy(Target.Decl.Parameters, 0, Length(Target.Decl.Parameters) - 1);
    mDropped := Target.Decl.Parameters[High(Target.Decl.Parameters)].Name;
    Parameters := TChangeSignature.ParameterList(Kept, False);
    if Parameters <> '' then
    begin
      Parameters := Copy(Parameters, 2, Length(Parameters) - 2);
    end;
  end
  else
  begin
    Parameters := ParameterText(Text, Tokens, Target.Decl);
  end;
  Doc := DocLines(mLines, Tokens[Target.Decl.StartToken].StartPos.Line, mDropped);
end;

procedure TOverloadWriter.AddDeclaration;
var
  mDecl: TInsertBuilder;
begin
  if not Target.HasDecl then
  begin
    if NeedsOverload(Target.Body) then
    begin
      Inserts := Inserts + [PlainInsert(TokenEnd(Tokens, Target.Body.EndToken), ' overload;')];
    end;
    Exit;
  end;
  mDecl := Default(TInsertBuilder);
  if NeedsOverload(Target.Decl) and (Target.Decl.LastToken = Target.Decl.EndToken) then
  begin
    mDecl.Add(' overload;');
  end
  else if NeedsOverload(Target.Decl) then
  begin
    Inserts := Inserts + [PlainInsert(TokenEnd(Tokens, Target.Decl.EndToken), ' overload;')];
  end;
  mDecl.Add(LineBreak + DocBlock(Doc, DeclIndent, LineBreak) + DeclIndent);
  AddHead(mDecl, Text, Tokens, Target.Decl, Parameters, True);
  Inserts := Inserts + [MakeInsert(TokenEnd(Tokens, Target.Decl.LastToken), mDecl)];
end;

procedure TOverloadWriter.AddCopyBody(var ABody: TInsertBuilder);
var
  mHead, mBegin, mInner, mInnerEnd: Integer;
begin
  // Rest wie im Original: lokale Deklarationen, Rumpf als Platzhalter 2.
  mHead := TokenEnd(Tokens, Target.Body.LastToken);
  mBegin := TokenEnd(Tokens, Target.BlockBegin);
  ABody.Add(Copy(Text, mHead + 1, mBegin - mHead));
  if Target.BlockEnd > Target.BlockBegin + 1 then
  begin
    mInner := Tokens[Target.BlockBegin + 1].Offset;
    mInnerEnd := TokenEnd(Tokens, Target.BlockEnd - 1);
    ABody.Add(Copy(Text, mBegin + 1, mInner - mBegin));
    ABody.Add(Copy(Text, mInner + 1, mInnerEnd - mInner), 2);
    ABody.Add(Copy(Text, mInnerEnd + 1, TokenEnd(Tokens, Target.BodyLast) - mInnerEnd));
  end
  else
  begin
    // Leerer Rumpf: eine eingerückte Zeile für den Platzhalter.
    ABody.Add(LineBreak + BodyIndent + '  ');
    ABody.Add('', 2);
    ABody.Add(LineBreak + BodyIndent + Copy(Text, Tokens[Target.BlockEnd].Offset + 1,
      TokenEnd(Tokens, Target.BodyLast) - Tokens[Target.BlockEnd].Offset));
  end;
end;

function TOverloadWriter.ForwardValue: string;
var
  mParameter: TSignatureParameter;
begin
  mParameter := Target.Decl.Parameters[High(Target.Decl.Parameters)];
  Result := '';
  if Assigned(Request.DefaultOf) then
  begin
    Result := Request.DefaultOf(mParameter.TypeName, Target.LastTypeOffset);
  end;
  if Result = '' then
  begin
    Result := TOverloads.DefaultValue(mParameter.TypeName);
  end;
  if Result = '' then
  begin
    Result := 'Default(' + mParameter.TypeName + ')';
  end;
end;

procedure TOverloadWriter.AddForwardBody(var ABody: TInsertBuilder);
var
  mCall, mArguments: string;
  mParameter: TSignatureParameter;
begin
  ABody.Add(LineBreak + BodyIndent + 'begin' + LineBreak + BodyIndent + '  ');
  mCall := '';
  if Target.Decl.IsFunction then
  begin
    mCall := 'Result := ';
  end;
  ABody.Add(mCall + Target.Name + '(');
  mArguments := '';
  for mParameter in Kept do
  begin
    mArguments := mArguments + mParameter.Name + ', ';
  end;
  ABody.Add(mArguments);
  ABody.Add(ForwardValue, 2);
  ABody.Add(');' + LineBreak + BodyIndent + 'end;');
end;

procedure TOverloadWriter.AddBody;
var
  mBody: TInsertBuilder;
begin
  mBody := Default(TInsertBuilder);
  mBody.Add(LineBreak + LineBreak);
  if not Target.HasDecl then
  begin
    mBody.Add(DocBlock(Doc, BodyIndent, LineBreak));
  end;
  AddHead(mBody, Text, Tokens, Target.Body, Parameters, not Target.HasDecl);
  if Request.Kind = TOverloadKind.Copy then
  begin
    AddCopyBody(mBody);
  end
  else
  begin
    AddForwardBody(mBody);
  end;
  mBody.Add('', 0);
  Inserts := Inserts + [MakeInsert(TokenEnd(Tokens, Target.BodyLast), mBody)];
end;

function TOverloadWriter.Outcome: TOverloadResult;
var
  mInserts: TArray<TInsert>;
  mInsert: TInsert;
  mField: TInsertField;
  mOldLines, mNewLines: TLineTable;
  mIndex, mShift: Integer;
begin
  Result := Default(TOverloadResult);
  mInserts := MergeInserts(Inserts);
  Result.NewText := Text;
  for mIndex := High(mInserts) downto 0 do
  begin
    Result.NewText := Copy(Result.NewText, 1, mInserts[mIndex].Offset) + mInserts[mIndex].Text +
      Copy(Result.NewText, mInserts[mIndex].Offset + 1, MaxInt);
  end;
  mOldLines := TLineTable.Build(Text);
  mNewLines := TLineTable.Build(Result.NewText);
  mShift := 0;
  for mInsert in mInserts do
  begin
    for mField in mInsert.Fields do
    begin
      Result.Placeholders := Result.Placeholders + [PlaceholderOf(mNewLines, mInsert.Offset + mShift, mField)];
    end;
    Result.Edits := Result.Edits + [TTextEdit.Create(TTextRange.Create(mOldLines.PositionAt(mInsert.Offset),
      mOldLines.PositionAt(mInsert.Offset)), mInsert.Text)];
    mShift := mShift + Length(mInsert.Text);
  end;
  if Target.Note <> '' then
  begin
    Result.Warnings := [Target.Note];
  end;
end;

{ TOverloadRequest }

class function TOverloadRequest.Create(AKind: TOverloadKind; const ADefaultOf: TOverloadDefaultFunc):
  TOverloadRequest;
begin
  Result.Kind := AKind;
  Result.DefaultOf := ADefaultOf;
end;

{ TOverloads: Build }

class function TOverloads.Build(const AText: string; ATree: TSyntaxTree; const ATarget: TOverloadTarget;
  AKind: TOverloadKind; out AResult: TOverloadResult; out AReason: string): Boolean;
begin
  Result := Build(AText, ATree, ATarget, TOverloadRequest.Create(AKind, nil), AResult, AReason);
end;

class function TOverloads.Build(const AText: string; ATree: TSyntaxTree; const ATarget: TOverloadTarget;
  const ARequest: TOverloadRequest; out AResult: TOverloadResult; out AReason: string): Boolean;
var
  mWriter: TOverloadWriter;
begin
  AResult := Default(TOverloadResult);
  AReason := ATarget.Reason(ARequest.Kind);
  if AReason <> '' then
  begin
    Exit(False);
  end;
  mWriter := Default(TOverloadWriter);
  mWriter.Text := AText;
  mWriter.Tokens := ATree.Tokens;
  mWriter.Target := ATarget;
  mWriter.Request := ARequest;
  mWriter.Prepare;
  mWriter.AddDeclaration;
  mWriter.AddBody;
  AResult := mWriter.Outcome;
  Result := True;
end;

end.
