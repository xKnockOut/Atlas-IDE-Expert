unit Atlas.Common.Rules.Builtin.Declarations.VariantRecords;

// Regel variant-record-managed-field aus Atlas.Common.Rules.Builtin.Declarations (#1071): verwalteter Typ im
// varianten Teil eines Records (wie E2154, E2418, E2569) und hinter file of (wie E2155, E2417).

interface

uses
  Atlas.Common.Rules.Contract;

type
  TVariantRecordManagedFieldRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Rules.Builtin.Declarations.Shared,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDeclarationsVariantRecordsText = (Title, MoveToFixed, UseShortString, RecordConstraint, TypeParam, NeedsFinal,
    NeedsInit, FileFinal, FileInit);

const
  cTexts: array[TDeclarationsVariantRecordsText] of TAtlasText = (
    (De: 'Verwalteter Typ im varianten Teil eines Records'; En: 'Managed type in the variant part of a record'),
    (De: '%s in den festen Teil verschieben'; En: 'Move %s to the fixed part'),
    (De: 'ShortString verwenden (höchstens 255 Zeichen)'; En: 'Use ShortString (at most 255 characters)'),
    (De: '%s: record einschränken'; En: '%s: constrain to record'),
    (De: 'Typparameter %s kann Finalisierung brauchen und ist im varianten Teil nicht erlaubt; record-Einschränkung ' +
      'verwenden (wie E2569).';
     En: 'Type parameter %s can need finalization and is not allowed in the variant part; use a record constraint ' +
      '(like E2569).'),
    (De: '%s braucht Finalisierung und ist im varianten Teil nicht erlaubt (wie E2154).';
     En: '%s needs finalization and is not allowed in the variant part (like E2154).'),
    (De: '%s braucht Initialisierung und ist im varianten Teil nicht erlaubt (wie E2418).';
     En: '%s needs initialization and is not allowed in the variant part (like E2418).'),
    (De: '%s braucht Finalisierung und ist in einem Dateityp nicht erlaubt (wie E2155).';
     En: '%s needs finalization and is not allowed in a file type (like E2155).'),
    (De: '%s braucht Initialisierung und ist in einem Dateityp nicht erlaubt (wie E2417).';
     En: '%s needs initialization and is not allowed in a file type (like E2417).'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Eine Gruppe von Typparametern bis zum nächsten ; auf oberster Ebene: Token des gesuchten Namens
  /// (-1, wenn er nicht dazugehört), Zahl der Namen, Einschränkung (:) und erstes Token hinter der Gruppe.</summary>
  TParamGroup = record
    Token: Integer;
    Count: Integer;
    Constrained: Boolean;
    Next: Integer;
  end;

/// <summary>Wertet ein Code-Token AToken (Index AIndex) einer Gruppe von Typparametern aus.</summary>
procedure ReadParamToken(var AGroup: TParamGroup; const AToken: TPascalToken; AIndex: Integer; const AName: string;
  var ADepth: Integer);
begin
  if AToken.IsSymbol('<') then
  begin
    Inc(ADepth);
  end
  else if AToken.IsSymbol('>') then
  begin
    Dec(ADepth);
  end
  else if (ADepth = 0) and AToken.IsSymbol(':') then
  begin
    AGroup.Constrained := True;
  end
  else if not AGroup.Constrained and (AToken.Kind = TPascalTokenKind.Identifier) then
  begin
    Inc(AGroup.Count);
    if SameText(AToken.Text, AName) then
    begin
      AGroup.Token := AIndex;
    end;
  end;
end;

/// <summary>Liest die Gruppe von Typparametern ab AIndex bis höchstens vor ALast; Namen vor dem :,
/// Einschränkungen dahinter.</summary>
function ReadParamGroup(const ATokens: TArray<TPascalToken>; AIndex, ALast: Integer; const AName: string):
  TParamGroup;
var
  mDepth: Integer;
begin
  Result := Default(TParamGroup);
  Result.Token := -1;
  mDepth := 0;
  while (AIndex < ALast) and not ((mDepth = 0) and ATokens[AIndex].IsSymbol(';')) do
  begin
    if not (ATokens[AIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      ReadParamToken(Result, ATokens[AIndex], AIndex, AName, mDepth);
    end;
    Inc(AIndex);
  end;
  Result.Next := AIndex + 1;
end;

/// <summary>Nennt die Liste der Typparameter AParams den Namen AName? Dann ist AToken sein Token, wenn er keine
/// Einschränkung hat (sonst -1), und AAlone, ob er der einzige Name seiner Gruppe ist.</summary>
function FindParam(const ATokens: TArray<TPascalToken>; AParams: TSyntaxNode; const AName: string;
  out AToken: Integer; out AAlone: Boolean): Boolean;
var
  mIndex, mLast: Integer;
  mGroup: TParamGroup;
begin
  Result := False;
  AToken := -1;
  AAlone := False;
  mIndex := TokenAtOffset(ATokens, AParams.StartOffset) + 1;
  mLast := TokenAtOffset(ATokens, AParams.EndOffset);
  while not Result and (mIndex < mLast) do
  begin
    mGroup := ReadParamGroup(ATokens, mIndex, mLast, AName);
    Result := mGroup.Token >= 0;
    mIndex := mGroup.Next;
  end;
  if Result then
  begin
    AAlone := mGroup.Count = 1;
    if not mGroup.Constrained then
    begin
      AToken := mGroup.Token;
    end;
  end;
end;

{ TVariantRecordManagedFieldRule }

function TVariantRecordManagedFieldRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('variant-record-managed-field', TRuleSeverity.Error,
    cTexts[TDeclarationsVariantRecordsText.Title].Text);
end;

procedure TVariantRecordManagedFieldRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  TypeKinds = [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.PointerType, TSyntaxKind.RecordType,
    TSyntaxKind.ClassType, TSyntaxKind.InterfaceType, TSyntaxKind.ClassOfType, TSyntaxKind.SetType,
    TSyntaxKind.EnumType, TSyntaxKind.ProcedureType, TSyntaxKind.SubrangeType, TSyntaxKind.FileType];
var
  Tokens: TArray<TPascalToken>;
  Lines: TArray<string>;
  LineBreak: string;
  Types: TManagedTypes;

  function IsCode(AIndex: Integer): Boolean;
  begin
    Result := not (Tokens[AIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
  end;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  function TypeNode(ANode: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      if ANode[Index].Kind in TypeKinds then
      begin
        Exit(ANode[Index]);
      end;
    end;
    Result := nil;
  end;

  // Token des Typparameters AName ohne Einschränkung in der umgebenden generischen Deklaration; -1 sonst.
  // AAlone: einziger Name seiner Gruppe (nur dann lässt sich ": record" anhängen).
  function UnconstrainedParam(ANode: TSyntaxNode; const AName: string; out AAlone: Boolean): Integer;
  var
    Decl, Params: TSyntaxNode;
    Found: Boolean;
  begin
    Result := -1;
    AAlone := False;
    Found := False;
    Decl := ANode.Parent;
    while not Found and (Decl <> nil) do
    begin
      if Decl.Kind = TSyntaxKind.TypeDecl then
      begin
        Params := Decl.FindChild(TSyntaxKind.GenericParams);
        Found := (Params <> nil) and FindParam(Tokens, Params, AName, Result, AAlone);
      end;
      Decl := Decl.Parent;
    end;
  end;

  // Feld vor das case des varianten Teils verschieben: einfügen vor case, im Zweig samt Trenner löschen.
  function MoveToFixedPart(AField, APart: TSyntaxNode): TRuleFix;
  var
    Item: TSyntaxNode;
    Text: string;
    Position, Remove: Integer;
    CaseToken, First, Last: Integer;
    Removal: TTextRange;
  begin
    Result := Default(TRuleFix);
    Item := AField.Parent;
    Position := 0;
    while Item[Position] <> AField do
    begin
      Inc(Position);
    end;
    Text := NodeText(AField);
    if Text.EndsWith(';') then
    begin
      Text := TrimRight(Copy(Text, 1, Length(Text) - 1));
    end;
    First := TokenAtOffset(Tokens, AField.StartOffset);
    Last := TokenAtOffset(Tokens, AField.EndOffset) - 1;
    if Tokens[Last].IsSymbol(';') and (Position < Item.ChildCount - 1) then
    begin
      // Bis vor das nächste Feld.
      Removal := TTextRange.Create(Tokens[First].StartPos, Item[Position + 1].StartPos);
    end
    else if Position > 0 then
    begin
      // Letztes Feld: ab dem ; des vorigen.
      Remove := First - 1;
      while (Remove > 0) and not IsCode(Remove) do
      begin
        Dec(Remove);
      end;
      if not Tokens[Remove].IsSymbol(';') then
      begin
        Exit;
      end;
      Removal := TTextRange.Create(Tokens[Remove].StartPos, Tokens[Last].EndPos);
    end
    else
    begin
      Removal := TTextRange.Create(Tokens[First].StartPos, Tokens[Last].EndPos);
    end;
    CaseToken := TokenAtOffset(Tokens, APart.StartOffset);
    Result := TRuleFix.Create(cTexts[TDeclarationsVariantRecordsText.MoveToFixed].Fmt([AField.Name]),
      [TRuleEdit.Create(TTextRange.Create(Tokens[CaseToken].StartPos, Tokens[CaseToken].StartPos),
      Text + ';' + LineBreak + TTextLines.IndentOf(Lines[Tokens[CaseToken].StartPos.Line])),
      TRuleEdit.Create(Removal, '')], False);
  end;

  function ShortStringFix(ATypeNode: TSyntaxNode): TArray<TRuleFix>;
  begin
    Result := nil;
    if MatchText(NodeText(ATypeNode), ['string', 'AnsiString', 'UnicodeString', 'WideString', 'RawByteString',
      'UTF8String']) then
    begin
      Result := [TRuleFix.Create(cTexts[TDeclarationsVariantRecordsText.UseShortString].Text,
        [TRuleEdit.Create(TTextRange.Create(ATypeNode.StartPos, ATypeNode.EndPos), 'ShortString')], False)];
    end;
  end;

  procedure CheckField(AField: TSyntaxNode);
  var
    TypeRef, Part: TSyntaxNode;
    TypeText, Kind: string;
    Param: Integer;
    Alone: Boolean;
    Fixes: TArray<TRuleFix>;
    Moved: TRuleFix;
  begin
    TypeRef := TypeNode(AField);
    if TypeRef = nil then
    begin
      Exit;
    end;
    TypeText := NodeText(TypeRef);
    Part := AField.Parent.Parent;
    Fixes := nil;
    // Nur der äußerste variante Teil hat einen festen Teil davor.
    if Part.Parent.Kind = TSyntaxKind.RecordType then
    begin
      Moved := MoveToFixedPart(AField, Part);
      if Moved.Title <> '' then
      begin
        Fixes := [Moved];
      end;
    end;
    Param := UnconstrainedParam(AField, TypeText, Alone);
    if Param >= 0 then
    begin
      if Alone then
      begin
        Fixes := Fixes + [TRuleFix.Create(cTexts[TDeclarationsVariantRecordsText.RecordConstraint].Fmt([TypeText]),
          [TRuleEdit.Create(TTextRange.Create(Tokens[Param].EndPos, Tokens[Param].EndPos), ': record')], False)];
      end;
      AReport.Add(TTextRange.Create(TypeRef.StartPos, TypeRef.EndPos),
        cTexts[TDeclarationsVariantRecordsText.TypeParam].Fmt([TypeText]), TRuleConfidence.High, Fixes);
      Exit;
    end;
    Kind := Types.Managed(TypeText, 0);
    if Kind <> '' then
    begin
      AReport.Add(TTextRange.Create(TypeRef.StartPos, TypeRef.EndPos),
        cTexts[TDeclarationsVariantRecordsText.NeedsFinal].Fmt([TypeText]), TRuleConfidence.High,
        ShortStringFix(TypeRef) + Fixes);
    end
    else if Types.CustomManaged(TypeText, 0) then
    begin
      AReport.Add(TTextRange.Create(TypeRef.StartPos, TypeRef.EndPos),
        cTexts[TDeclarationsVariantRecordsText.NeedsInit].Fmt([TypeText]), TRuleConfidence.High, Fixes);
    end;
  end;

  procedure CheckFile(AFile: TSyntaxNode);
  var
    TypeRef: TSyntaxNode;
    TypeText: string;
  begin
    TypeRef := TypeNode(AFile);
    if TypeRef = nil then
    begin
      Exit;
    end;
    TypeText := NodeText(TypeRef);
    if Types.Managed(TypeText, 0) <> '' then
    begin
      AReport.Add(TTextRange.Create(TypeRef.StartPos, TypeRef.EndPos),
        cTexts[TDeclarationsVariantRecordsText.FileFinal].Fmt([TypeText]), TRuleConfidence.High,
        ShortStringFix(TypeRef));
    end
    else if Types.CustomManaged(TypeText, 0) then
    begin
      AReport.Add(TTextRange.Create(TypeRef.StartPos, TypeRef.EndPos),
        cTexts[TDeclarationsVariantRecordsText.FileInit].Fmt([TypeText]), TRuleConfidence.High, nil);
    end;
  end;

var
  Stack: TArray<TSyntaxNode>;
  Count, Index: Integer;
  Node: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Types := TManagedTypes.Create(AContext.Tree, AContext.Text, AContext.Index);
  try
    // Ohne Rekursion durch den Baum (#1094).
    SetLength(Stack, 64);
    Stack[0] := AContext.Tree.Root;
    Count := 1;
    while Count > 0 do
    begin
      Dec(Count);
      Node := Stack[Count];
      if (Node.Kind = TSyntaxKind.Field) and (Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.CaseItem) and
        (Node.Parent.Parent <> nil) and (Node.Parent.Parent.Kind = TSyntaxKind.VariantPart) then
      begin
        CheckField(Node);
      end
      else if Node.Kind = TSyntaxKind.FileType then
      begin
        CheckFile(Node);
      end;
      if Count + Node.ChildCount > Length(Stack) then
      begin
        SetLength(Stack, 2 * (Count + Node.ChildCount));
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Stack[Count] := Node[Index];
        Inc(Count);
      end;
    end;
  finally
    Types.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Declarations.VariantRecords', cTexts);

end.
