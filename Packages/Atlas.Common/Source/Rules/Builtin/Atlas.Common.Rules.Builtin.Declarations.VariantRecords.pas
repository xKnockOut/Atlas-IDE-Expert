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
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.ManagedTypes,
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
  cTypeKinds = [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.PointerType, TSyntaxKind.RecordType,
    TSyntaxKind.ClassType, TSyntaxKind.InterfaceType, TSyntaxKind.ClassOfType, TSyntaxKind.SetType,
    TSyntaxKind.EnumType, TSyntaxKind.ProcedureType, TSyntaxKind.SubrangeType, TSyntaxKind.FileType];
var
  mTokens: TArray<TPascalToken>;
  mLines: TArray<string>;
  mLineBreak: string;
  mTypes: TManagedTypes;

  function IsCode(AIndex: Integer): Boolean;
  begin
    Result := not (mTokens[AIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
  end;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  function TypeNode(ANode: TSyntaxNode): TSyntaxNode;
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      if ANode[mIndex].Kind in cTypeKinds then
      begin
        Exit(ANode[mIndex]);
      end;
    end;
    Result := nil;
  end;

  // Token des Typparameters AName ohne Einschränkung in der umgebenden generischen Deklaration; -1 sonst.
  // AAlone: einziger Name seiner Gruppe (nur dann lässt sich ": record" anhängen).
  function UnconstrainedParam(ANode: TSyntaxNode; const AName: string; out AAlone: Boolean): Integer;
  var
    mDecl, mParams: TSyntaxNode;
    mFound: Boolean;
  begin
    Result := -1;
    AAlone := False;
    mFound := False;
    mDecl := ANode.Parent;
    while not mFound and (mDecl <> nil) do
    begin
      if mDecl.Kind = TSyntaxKind.TypeDecl then
      begin
        mParams := mDecl.FindChild(TSyntaxKind.GenericParams);
        mFound := (mParams <> nil) and FindParam(mTokens, mParams, AName, Result, AAlone);
      end;
      mDecl := mDecl.Parent;
    end;
  end;

  // Feld vor das case des varianten Teils verschieben: einfügen vor case, im Zweig samt Trenner löschen.
  function MoveToFixedPart(AField, APart: TSyntaxNode): TRuleFix;
  var
    mItem: TSyntaxNode;
    mText: string;
    mPosition, mRemove: Integer;
    mCaseToken, mFirst, mLast: Integer;
    mRemoval: TTextRange;
  begin
    Result := Default(TRuleFix);
    mItem := AField.Parent;
    mPosition := 0;
    while mItem[mPosition] <> AField do
    begin
      Inc(mPosition);
    end;
    mText := NodeText(AField);
    if mText.EndsWith(';') then
    begin
      mText := TrimRight(Copy(mText, 1, Length(mText) - 1));
    end;
    mFirst := TokenAtOffset(mTokens, AField.StartOffset);
    mLast := TokenAtOffset(mTokens, AField.EndOffset) - 1;
    if mTokens[mLast].IsSymbol(';') and (mPosition < mItem.ChildCount - 1) then
    begin
      // Bis vor das nächste Feld.
      mRemoval := TTextRange.Create(mTokens[mFirst].StartPos, mItem[mPosition + 1].StartPos);
    end
    else if mPosition > 0 then
    begin
      // Letztes Feld: ab dem ; des vorigen.
      mRemove := mFirst - 1;
      while (mRemove > 0) and not IsCode(mRemove) do
      begin
        Dec(mRemove);
      end;
      if not mTokens[mRemove].IsSymbol(';') then
      begin
        Exit;
      end;
      mRemoval := TTextRange.Create(mTokens[mRemove].StartPos, mTokens[mLast].EndPos);
    end
    else
    begin
      mRemoval := TTextRange.Create(mTokens[mFirst].StartPos, mTokens[mLast].EndPos);
    end;
    mCaseToken := TokenAtOffset(mTokens, APart.StartOffset);
    Result := TRuleFix.Create(cTexts[TDeclarationsVariantRecordsText.MoveToFixed].Fmt([AField.Name]),
      [TRuleEdit.Create(TTextRange.Create(mTokens[mCaseToken].StartPos, mTokens[mCaseToken].StartPos),
      mText + ';' + mLineBreak + TTextLines.IndentOf(mLines[mTokens[mCaseToken].StartPos.Line])),
      TRuleEdit.Create(mRemoval, '')], False);
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
    mTypeRef, mPart: TSyntaxNode;
    mTypeText, mKind: string;
    mParam: Integer;
    mAlone: Boolean;
    mFixes: TArray<TRuleFix>;
    mMoved: TRuleFix;
  begin
    mTypeRef := TypeNode(AField);
    if mTypeRef = nil then
    begin
      Exit;
    end;
    mTypeText := NodeText(mTypeRef);
    mPart := AField.Parent.Parent;
    mFixes := nil;
    // Nur der äußerste variante Teil hat einen festen Teil davor.
    if mPart.Parent.Kind = TSyntaxKind.RecordType then
    begin
      mMoved := MoveToFixedPart(AField, mPart);
      if mMoved.Title <> '' then
      begin
        mFixes := [mMoved];
      end;
    end;
    mParam := UnconstrainedParam(AField, mTypeText, mAlone);
    if mParam >= 0 then
    begin
      if mAlone then
      begin
        mFixes := mFixes + [TRuleFix.Create(cTexts[TDeclarationsVariantRecordsText.RecordConstraint].Fmt([mTypeText]),
          [TRuleEdit.Create(TTextRange.Create(mTokens[mParam].EndPos, mTokens[mParam].EndPos), ': record')], False)];
      end;
      AReport.Add(TTextRange.Create(mTypeRef.StartPos, mTypeRef.EndPos),
        cTexts[TDeclarationsVariantRecordsText.TypeParam].Fmt([mTypeText]), TRuleConfidence.High, mFixes);
      Exit;
    end;
    mKind := mTypes.Managed(mTypeText, 0);
    if mKind <> '' then
    begin
      AReport.Add(TTextRange.Create(mTypeRef.StartPos, mTypeRef.EndPos),
        cTexts[TDeclarationsVariantRecordsText.NeedsFinal].Fmt([mTypeText]), TRuleConfidence.High,
        ShortStringFix(mTypeRef) + mFixes);
    end
    else if mTypes.CustomManaged(mTypeText, 0) then
    begin
      AReport.Add(TTextRange.Create(mTypeRef.StartPos, mTypeRef.EndPos),
        cTexts[TDeclarationsVariantRecordsText.NeedsInit].Fmt([mTypeText]), TRuleConfidence.High, mFixes);
    end;
  end;

  procedure CheckFile(AFile: TSyntaxNode);
  var
    mTypeRef: TSyntaxNode;
    mTypeText: string;
  begin
    mTypeRef := TypeNode(AFile);
    if mTypeRef = nil then
    begin
      Exit;
    end;
    mTypeText := NodeText(mTypeRef);
    if mTypes.Managed(mTypeText, 0) <> '' then
    begin
      AReport.Add(TTextRange.Create(mTypeRef.StartPos, mTypeRef.EndPos),
        cTexts[TDeclarationsVariantRecordsText.FileFinal].Fmt([mTypeText]), TRuleConfidence.High,
        ShortStringFix(mTypeRef));
    end
    else if mTypes.CustomManaged(mTypeText, 0) then
    begin
      AReport.Add(TTextRange.Create(mTypeRef.StartPos, mTypeRef.EndPos),
        cTexts[TDeclarationsVariantRecordsText.FileInit].Fmt([mTypeText]), TRuleConfidence.High, nil);
    end;
  end;

var
  mStack: TArray<TSyntaxNode>;
  mCount, mIndex: Integer;
  mNode: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mLines := TTextLines.SplitLines(AContext.Text, mLineBreak);
  mTypes := TManagedTypes.Create(AContext.Tree, AContext.Text, AContext.Index);
  try
    // Ohne Rekursion durch den Baum (#1094).
    SetLength(mStack, 64);
    mStack[0] := AContext.Tree.Root;
    mCount := 1;
    while mCount > 0 do
    begin
      Dec(mCount);
      mNode := mStack[mCount];
      if (mNode.Kind = TSyntaxKind.Field) and (mNode.Parent <> nil) and (mNode.Parent.Kind = TSyntaxKind.CaseItem) and
        (mNode.Parent.Parent <> nil) and (mNode.Parent.Parent.Kind = TSyntaxKind.VariantPart) then
      begin
        CheckField(mNode);
      end
      else if mNode.Kind = TSyntaxKind.FileType then
      begin
        CheckFile(mNode);
      end;
      if mCount + mNode.ChildCount > Length(mStack) then
      begin
        SetLength(mStack, 2 * (mCount + mNode.ChildCount));
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mStack[mCount] := mNode[mIndex];
        Inc(mCount);
      end;
    end;
  finally
    mTypes.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Declarations.VariantRecords', cTexts);

end.
