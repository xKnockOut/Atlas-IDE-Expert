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
    /// <summary>Wie oben; ADefault liefert den Standardwert des weggelassenen Parameters (Namensauflösung).</summary>
    class function Build(const AText: string; ATree: TSyntaxTree; const ATarget: TOverloadTarget;
      AKind: TOverloadKind; const ADefault: TOverloadDefaultFunc; out AResult: TOverloadResult;
      out AReason: string): Boolean; overload; static;
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
    Result := TOverloads.ForwardTitle
  else
    Result := TOverloads.CopyTitle;
end;

function TOverloadTarget.Reason(AKind: TOverloadKind): string;
begin
  if AKind = TOverloadKind.Forward then
    Result := ForwardReason
  else
    Result := CopyReason;
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
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
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
      Break;
    if (ATokens[Index].Offset >= AHeader.StartOffset) and (ATokens[Index].Kind = TPascalTokenKind.Identifier) and
      SameText(ATokens[Index].Text, Name) then
      Exit(Index);
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
    for Index := 0 to High(A) do
      if not SameText(StringReplace(A[Index], ' ', '', [rfReplaceAll]),
        StringReplace(B[Index], ' ', '', [rfReplaceAll])) then
        Exit(False);
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
        for Index := 0 to ANode.ChildCount - 1 do
          if ANode[Index].Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType] then
            Found := ANode[Index];
    end);
  Result := Found;
end;

/// <summary>Köpfe aller Routinen namens AName: in der Klasse AType bzw. auf Unit-Ebene (beide Teile).</summary>
function Overloads(ATree: TSyntaxTree; const AText, AName: string; AType: TSyntaxNode): TArray<TSignatureHeader>;
var
  Section: TSyntaxNode;
  Index, Part: Integer;
  Header: TSignatureHeader;
  Kind: TSyntaxKind;
begin
  Result := nil;
  if AType <> nil then
  begin
    for Index := 0 to AType.ChildCount - 1 do
      if (AType[Index].Kind = TSyntaxKind.RoutineHeader) and SameText(AType[Index].Name, AName) and
        ReadNode(AText, ATree, AType[Index], Header) then
        Result := Result + [Header];
    Exit;
  end;
  for Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] do
  begin
    Section := ATree.Root.FindChild(Kind);
    if Section = nil then
      Continue;
    for Part := 0 to Section.ChildCount - 1 do
      if (Section[Part].Kind = TSyntaxKind.RoutineDecl) and SameText(Section[Part].Name, AName) and
        ReadNode(AText, ATree, TRoutineParts.HeaderOf(Section[Part]), Header) then
        Result := Result + [Header];
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
    Exit;
  Count := 0;
  Single := nil;
  SingleHeader := Default(TSignatureHeader);
  for Index := 0 to Section.ChildCount - 1 do
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
  Candidates: TArray<TSignatureHeader>;
  Candidate: TSignatureHeader;
  Section: TSyntaxNode;
  Index: Integer;
  Header: TSignatureHeader;
begin
  ADecl := Default(TSignatureHeader);
  Candidates := nil;
  if AType <> nil then
    Candidates := Overloads(ATree, AText, AName, AType)
  else
  begin
    Section := ATree.Root.FindChild(TSyntaxKind.InterfaceSection);
    if Section <> nil then
      for Index := 0 to Section.ChildCount - 1 do
        if (Section[Index].Kind = TSyntaxKind.RoutineDecl) and SameText(Section[Index].Name, AName) and
          ReadNode(AText, ATree, TRoutineParts.HeaderOf(Section[Index]), Header) then
          Candidates := Candidates + [Header];
  end;
  for Candidate in Candidates do
    if SameTypes(Candidate.ParamTypes, ABody.ParamTypes) then
    begin
      ADecl := Candidate;
      Exit(True);
    end;
  Result := (Length(Candidates) = 1) and (ABody.OpenToken < 0);
  if Result then
    ADecl := Candidates[0];
end;

/// <summary>Anfang des Typs des letzten Parameters im Kopf AHeader; -1 ohne.</summary>
function LastTypeOffset(AHeader: TSyntaxNode): Integer;
var
  Parameters, Parameter: TSyntaxNode;
begin
  Result := -1;
  if AHeader = nil then
    Exit;
  Parameters := AHeader.FindChild(TSyntaxKind.Parameters);
  if (Parameters = nil) or (Parameters.ChildCount = 0) then
    Exit;
  Parameter := Parameters[Parameters.ChildCount - 1];
  if (Parameter.ChildCount > 0) and (Parameter[Parameter.ChildCount - 1].Kind = TSyntaxKind.TypeReference) then
    Result := Parameter[Parameter.ChildCount - 1].StartOffset
  else if Parameter.ChildCount > 0 then
    Result := Parameter[0].StartOffset;
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
        Found := ANode;
    end);
  Result := Found;
end;

function IsModifier(const AModifier, AWord: string): Boolean;
var
  Part: string;
begin
  for Part in AModifier.Split([' ']) do
    if SameText(Part, AWord) then
      Exit(True);
  Result := False;
end;

{ TOverloads }

class function TOverloads.Target(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  out ATarget: TOverloadTarget): Boolean;
var
  Lines: TLineTable;
  Offset: Integer;
  Routine, DeclHeader, BodyNode, TypeNode, Block, Found: TSyntaxNode;
  Tokens: TArray<TPascalToken>;
  Header: TSignatureHeader;
  Existing: TArray<TSignatureHeader>;
  Wanted: TArray<string>;
  Last: TSignatureParameter;
  Qualified: string;
begin
  Result := False;
  ATarget := Default(TOverloadTarget);
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Tokens := ATree.Tokens;
  Lines := TLineTable.Build(AText);
  Offset := Lines.OffsetAt(APosition);
  DeclHeader := nil;
  BodyNode := nil;
  TypeNode := nil;
  Routine := TRoutineParts.RoutineWithHeaderAt(ATree, Offset);
  if Routine <> nil then
  begin
    if (Routine.Parent = nil) or not (Routine.Parent.Kind in [TSyntaxKind.InterfaceSection,
      TSyntaxKind.ImplementationSection]) then
      Exit;
    if Routine.FindChild(TSyntaxKind.Block) <> nil then
      BodyNode := Routine
    else if Routine.Parent.Kind = TSyntaxKind.InterfaceSection then
      DeclHeader := TRoutineParts.HeaderOf(Routine)
    else
      Exit;
  end
  else
  begin
    // Kopf in einer Klasse bzw. einem Record.
    Found := nil;
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := TRoutineParts.Encloses(ANode, Offset);
        if Result and (ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode.Parent <> nil) and
          (ANode.Parent.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType]) then
          Found := ANode;
      end);
    if (Found = nil) or (Found.Parent.Parent = nil) then
      Exit;
    DeclHeader := Found;
    TypeNode := Found.Parent;
    ATarget.Container := Found.Parent.Parent.Name;
  end;

  if DeclHeader <> nil then
  begin
    if not ReadNode(AText, ATree, DeclHeader, ATarget.Decl) then
      Exit;
    ATarget.HasDecl := True;
    ATarget.Name := ShortName(ATarget.Decl.QualifiedName);
    Qualified := ATarget.Name;
    if ATarget.Container <> '' then
      Qualified := ATarget.Container + '.' + ATarget.Name;
    BodyNode := FindBody(ATree, AText, Qualified, ATarget.Decl, ATarget.Body);
    if BodyNode = nil then
      Exit;
    ATarget.LastTypeOffset := LastTypeOffset(DeclHeader);
  end
  else
  begin
    if not ReadNode(AText, ATree, TRoutineParts.HeaderOf(BodyNode), ATarget.Body) then
      Exit;
    ATarget.Name := ShortName(ATarget.Body.QualifiedName);
    if Pos('.', ATarget.Body.QualifiedName) > 0 then
    begin
      ATarget.Container := Copy(ATarget.Body.QualifiedName, 1, LastDelimiter('.', ATarget.Body.QualifiedName) - 1);
      if Pos('.', ATarget.Container) > 0 then
        ATarget.Container := ShortName(ATarget.Container);
      TypeNode := FindType(ATree.Root, ATarget.Container);
      if TypeNode = nil then
        Exit;
    end;
    if FindDecl(ATree, AText, TypeNode, ATarget.Name, ATarget.Body, Header) then
    begin
      ATarget.Decl := Header;
      ATarget.HasDecl := True;
    end
    else if ATarget.Container <> '' then
      Exit
    else
      ATarget.Decl := ATarget.Body;
    // Typ des letzten Parameters: aus der Deklaration, sonst aus dem Kopf der Implementierung.
    if ATarget.HasDecl then
      ATarget.LastTypeOffset := LastTypeOffset(HeaderNodeAt(ATree, Tokens[ATarget.Decl.NameToken].Offset))
    else
      ATarget.LastTypeOffset := LastTypeOffset(TRoutineParts.HeaderOf(BodyNode));
  end;

  Block := BodyNode.FindChild(TSyntaxKind.Block);
  if Block = nil then
    Exit;
  ATarget.BlockBegin := TRoutineBody.TokenAt(Tokens, Block.StartOffset);
  ATarget.BodyLast := TChangeSignature.BodyEnd(ATree, ATarget.Body);
  if (ATarget.BlockBegin > High(Tokens)) or not Tokens[ATarget.BlockBegin].IsKeyword('begin') or
    (ATarget.BodyLast < 0) then
    Exit;
  ATarget.BlockEnd := ATarget.BodyLast;
  while (ATarget.BlockEnd > ATarget.BlockBegin) and not Tokens[ATarget.BlockEnd].IsKeyword('end') do
    Dec(ATarget.BlockEnd);
  if ATarget.BlockEnd <= ATarget.BlockBegin then
    Exit;

  if ATarget.Decl.Keyword = 'destructor' then
  begin
    ATarget.CopyReason := DestructorReason;
    ATarget.ForwardReason := DestructorReason;
  end
  else if (ATarget.Decl.NameToken < High(Tokens)) and Tokens[ATarget.Decl.NameToken + 1].IsSymbol('<') then
  begin
    ATarget.CopyReason := GenericReason;
    ATarget.ForwardReason := GenericReason;
  end
  else if Length(ATarget.Decl.Parameters) = 0 then
    ATarget.ForwardReason := NoParameterReason
  else
  begin
    Last := ATarget.Decl.Parameters[High(ATarget.Decl.Parameters)];
    if IsModifier(Last.Modifier, 'var') or IsModifier(Last.Modifier, 'out') or (Last.TypeName = '') then
      ATarget.ForwardReason := Format(VarParameterReason, [Last.Name])
    else
    begin
      Wanted := Copy(ATarget.Decl.ParamTypes, 0, Length(ATarget.Decl.Parameters) - 1);
      Existing := Overloads(ATree, AText, ATarget.Name, TypeNode);
      for Header in Existing do
        if SameTypes(Header.ParamTypes, Wanted) then
        begin
          ATarget.ForwardReason := Format(ExistsReason, [ATarget.Name, string.Join(', ', Wanted)]);
          Break;
        end;
    end;
  end;
  if ATarget.Decl.HasDirective('override') then
    ATarget.Note := Format(OverrideNote, [ATarget.Name]);
  Result := True;
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
    Name := Copy(Name, Length('system.') + 1, MaxInt);
  if StartsText('array of ', Name) then
    Result := '[]'
  else if IndexText(Name, Numbers) >= 0 then
    Result := '0'
  else if IndexText(Name, Strings) >= 0 then
    Result := ''''''
  else if IndexText(Name, Chars) >= 0 then
    Result := '#0'
  else if IndexText(Name, Booleans) >= 0 then
    Result := 'False'
  else if IndexText(Name, Pointers) >= 0 then
    Result := 'nil'
  else
    Result := '';
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
    Dec(Line);
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
      Continue;
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
    Result := Result + AIndent + Line + ALineBreak;
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
    if Parameter.DefaultValue <> '' then
      HasDefault := True;
  if HasDefault or (AHeader.OpenToken < 0) then
  begin
    Result := TChangeSignature.ParameterList(AHeader.Parameters, False);
    if Result <> '' then
      Result := Copy(Result, 2, Length(Result) - 2);
  end
  else
    Result := Copy(AText, TokenEnd(ATokens, AHeader.OpenToken) + 1,
      ATokens[AHeader.CloseToken].Offset - TokenEnd(ATokens, AHeader.OpenToken));
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
    From := TokenEnd(ATokens, AHeader.CloseToken)
  else
    From := TokenEnd(ATokens, AHeader.NameToken);
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
    ABuilder.Add(TChangeSignature.OverloadDirectives(AHeader, False));
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
    Result[Index].Sequence := Index;
  TArray.Sort<TInsert>(Result, TComparer<TInsert>.Construct(
    function(const A, B: TInsert): Integer
    begin
      if A.Offset <> B.Offset then
        Result := A.Offset - B.Offset
      else
        Result := A.Sequence - B.Sequence;
    end));
end;

class function TOverloads.Build(const AText: string; ATree: TSyntaxTree; const ATarget: TOverloadTarget;
  AKind: TOverloadKind; out AResult: TOverloadResult; out AReason: string): Boolean;
begin
  Result := Build(AText, ATree, ATarget, AKind, nil, AResult, AReason);
end;

class function TOverloads.Build(const AText: string; ATree: TSyntaxTree; const ATarget: TOverloadTarget;
  AKind: TOverloadKind; const ADefault: TOverloadDefaultFunc; out AResult: TOverloadResult;
  out AReason: string): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Lines: TArray<string>;
  OldLines, NewLines: TLineTable;
  LineBreak, DeclIndent, BodyIndent, Parameters, Dropped, Value, Call, Arguments: string;
  Inserts: TArray<TInsert>;
  Decl, Body: TInsertBuilder;
  Kept: TArray<TSignatureParameter>;
  Parameter: TSignatureParameter;
  Index, Shift, Inner, InnerEnd: Integer;
  Field: TInsertField;
  Placeholder: TOverloadPlaceholder;
  Doc: TArray<string>;
  Insert: TInsert;
begin
  AResult := Default(TOverloadResult);
  AReason := ATarget.Reason(AKind);
  if AReason <> '' then
    Exit(False);
  Result := True;
  Tokens := ATree.Tokens;
  Lines := TTextLines.SplitLines(AText);
  LineBreak := TTextLines.LineBreakOf(AText);
  OldLines := TLineTable.Build(AText);
  DeclIndent := TTextLines.IndentOf(Lines[Tokens[ATarget.Decl.StartToken].StartPos.Line]);
  BodyIndent := TTextLines.IndentOf(Lines[Tokens[ATarget.Body.StartToken].StartPos.Line]);
  Inserts := nil;

  Dropped := '';
  if AKind = TOverloadKind.Forward then
  begin
    Kept := Copy(ATarget.Decl.Parameters, 0, Length(ATarget.Decl.Parameters) - 1);
    Dropped := ATarget.Decl.Parameters[High(ATarget.Decl.Parameters)].Name;
    Parameters := TChangeSignature.ParameterList(Kept, False);
    if Parameters <> '' then
      Parameters := Copy(Parameters, 2, Length(Parameters) - 2);
  end
  else
    Parameters := ParameterText(AText, Tokens, ATarget.Decl);
  Doc := DocLines(Lines, Tokens[ATarget.Decl.StartToken].StartPos.Line, Dropped);

  // Deklaration: Kopie hinter dem Original, das selbst overload bekommt.
  if ATarget.HasDecl then
  begin
    Decl := Default(TInsertBuilder);
    if NeedsOverload(ATarget.Decl) then
    begin
      if ATarget.Decl.LastToken = ATarget.Decl.EndToken then
        Decl.Add(' overload;')
      else
        Inserts := Inserts + [PlainInsert(TokenEnd(Tokens, ATarget.Decl.EndToken), ' overload;')];
    end;
    Decl.Add(LineBreak + DocBlock(Doc, DeclIndent, LineBreak) + DeclIndent);
    AddHead(Decl, AText, Tokens, ATarget.Decl, Parameters, True);
    Inserts := Inserts + [MakeInsert(TokenEnd(Tokens, ATarget.Decl.LastToken), Decl)];
  end
  else if NeedsOverload(ATarget.Body) then
    Inserts := Inserts + [PlainInsert(TokenEnd(Tokens, ATarget.Body.EndToken), ' overload;')];

  // Implementierung hinter der des Originals.
  Body := Default(TInsertBuilder);
  Body.Add(LineBreak + LineBreak);
  if not ATarget.HasDecl then
    Body.Add(DocBlock(Doc, BodyIndent, LineBreak));
  AddHead(Body, AText, Tokens, ATarget.Body, Parameters, not ATarget.HasDecl);
  if AKind = TOverloadKind.Copy then
  begin
    // Rest wie im Original: lokale Deklarationen, Rumpf als Platzhalter 2.
    Body.Add(Copy(AText, TokenEnd(Tokens, ATarget.Body.LastToken) + 1,
      TokenEnd(Tokens, ATarget.BlockBegin) - TokenEnd(Tokens, ATarget.Body.LastToken)));
    if ATarget.BlockEnd > ATarget.BlockBegin + 1 then
    begin
      Inner := Tokens[ATarget.BlockBegin + 1].Offset;
      InnerEnd := TokenEnd(Tokens, ATarget.BlockEnd - 1);
      Body.Add(Copy(AText, TokenEnd(Tokens, ATarget.BlockBegin) + 1, Inner - TokenEnd(Tokens, ATarget.BlockBegin)));
      Body.Add(Copy(AText, Inner + 1, InnerEnd - Inner), 2);
      Body.Add(Copy(AText, InnerEnd + 1, TokenEnd(Tokens, ATarget.BodyLast) - InnerEnd));
    end
    else
    begin
      // Leerer Rumpf: eine eingerückte Zeile für den Platzhalter.
      Body.Add(LineBreak + BodyIndent + '  ');
      Body.Add('', 2);
      Body.Add(LineBreak + BodyIndent + Copy(AText, Tokens[ATarget.BlockEnd].Offset + 1,
        TokenEnd(Tokens, ATarget.BodyLast) - Tokens[ATarget.BlockEnd].Offset));
    end;
  end
  else
  begin
    Body.Add(LineBreak + BodyIndent + 'begin' + LineBreak + BodyIndent + '  ');
    Call := '';
    if ATarget.Decl.IsFunction then
      Call := 'Result := ';
    Body.Add(Call + ATarget.Name + '(');
    Arguments := '';
    for Parameter in Kept do
      Arguments := Arguments + Parameter.Name + ', ';
    Body.Add(Arguments);
    Parameter := ATarget.Decl.Parameters[High(ATarget.Decl.Parameters)];
    Value := '';
    if Assigned(ADefault) then
      Value := ADefault(Parameter.TypeName, ATarget.LastTypeOffset);
    if Value = '' then
      Value := DefaultValue(Parameter.TypeName);
    if Value = '' then
      Value := 'Default(' + Parameter.TypeName + ')';
    Body.Add(Value, 2);
    Body.Add(');' + LineBreak + BodyIndent + 'end;');
  end;
  Body.Add('', 0);
  Inserts := Inserts + [MakeInsert(TokenEnd(Tokens, ATarget.BodyLast), Body)];

  // Text danach und Platzhalter darin.
  Inserts := MergeInserts(Inserts);
  AResult.NewText := AText;
  for Index := High(Inserts) downto 0 do
    AResult.NewText := Copy(AResult.NewText, 1, Inserts[Index].Offset) + Inserts[Index].Text +
      Copy(AResult.NewText, Inserts[Index].Offset + 1, MaxInt);
  NewLines := TLineTable.Build(AResult.NewText);
  Shift := 0;
  for Insert in Inserts do
  begin
    for Field in Insert.Fields do
    begin
      Placeholder.Number := Field.Number;
      Placeholder.Range := TTextRange.Create(NewLines.PositionAt(Insert.Offset + Shift + Field.Start),
        NewLines.PositionAt(Insert.Offset + Shift + Field.Start + Field.Length));
      AResult.Placeholders := AResult.Placeholders + [Placeholder];
    end;
    AResult.Edits := AResult.Edits + [TTextEdit.Create(TTextRange.Create(OldLines.PositionAt(Insert.Offset),
      OldLines.PositionAt(Insert.Offset)), Insert.Text)];
    Shift := Shift + Length(Insert.Text);
  end;
  if ATarget.Note <> '' then
    AResult.Warnings := [ATarget.Note];
end;

end.
