unit Atlas.Common.Rules.Builtin.Style.Declarations;

// Stilregeln zu Deklarationen, registriert mit den übrigen Stilregeln (RegisterStyleRules):
//   public-field     Feld im public- oder published-Abschnitt einer Klasse (Standard aus, #940); Records nur mit
//                    includeRecords. Der Abschnitt ohne Sichtbarkeitswort zählt nur bei Klassen ohne Vorfahren bzw.
//                    mit TObject: sonst stehen dort die Felder des Designers. Korrektur „Feld kapseln“: FName im
//                    private-Abschnitt am Ende der Klasse, dazu property Name read FName write FName (wie
//                    /encapsulate, #298). Typen unter einem private-/protected-Abschnitt (protected type
//                    TEntry = class …) sind Hilfsklassen ihrer Klasse und bleiben still
//   global-variable  var bzw. threadvar im interface-Teil einer Unit (Standard aus, #941); die Formularvariable des
//                    Designers (frmHaupt: TfrmHaupt) nur mit includeFormVariables

interface

uses
  Atlas.Common.Rules.Contract;

type
  TPublicFieldRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TGlobalVariableRule = class(TInterfacedObject, IRule)
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
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Options,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TStyleDeclarationsText = (PublicFieldTitle, Encapsulate, PublicField, GlobalTitle, Global);

const
  cTexts: array[TStyleDeclarationsText] of TAtlasText = (
    (De: 'Öffentliches Feld'; En: 'Public field'),
    (De: 'Feld kapseln'; En: 'Encapsulate field'),
    (De: 'Öffentliches Feld %s; eine Property hält die Klasse änderbar.';
     En: 'Public field %s; a property keeps the class changeable.'),
    (De: 'Globale Variable im interface'; En: 'Global variable in the interface'),
    (De: 'Globale Variable %s ist in jeder Unit sichtbar, die diese verwendet.';
     En: 'Global variable %s is visible in every unit that uses this one.'));

{$SCOPEDENUMS OFF}

{ TPublicFieldRule }

function TPublicFieldRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('public-field', TRuleSeverity.Hint,
    cTexts[TStyleDeclarationsText.PublicFieldTitle].Text, True);
end;

procedure TPublicFieldRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mLines: TArray<string>;
  mLineBreak: string;
  mIncludeRecords: Boolean;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  function LineOf(ALine: Integer): string;
  begin
    Result := '';
    if (ALine >= 0) and (ALine <= High(mLines)) then
    begin
      Result := mLines[ALine];
    end;
  end;

  // Steht ANode allein in seiner Zeile (nur Leerraum davor und dahinter)?
  function AloneInLine(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.StartPos.Line = ANode.EndPos.Line) and
      (Trim(Copy(LineOf(ANode.StartPos.Line), 1, ANode.StartPos.Character)) = '') and
      (Trim(Copy(LineOf(ANode.EndPos.Line), ANode.EndPos.Character + 1, MaxInt)) = '');
  end;

  function HasMember(AType: TSyntaxNode; const AName: string): Boolean;
  var
    mIndex: Integer;
    mName: string;
  begin
    for mIndex := 0 to AType.ChildCount - 1 do
    begin
      if AType[mIndex].Kind in [TSyntaxKind.Field, TSyntaxKind.PropertyDecl, TSyntaxKind.RoutineHeader] then
      begin
        for mName in AType[mIndex].Name.Split([',']) do
        begin
          if SameText(Trim(mName), AName) then
          begin
            Exit(True);
          end;
        end;
      end;
    end;
    Result := False;
  end;

  function FieldNameOf(const AName: string): string;
  begin
    Result := 'F' + UpperCase(Copy(AName, 1, 1)) + Copy(AName, 2, MaxInt);
  end;

  // Name mit F-Präfix: Die Property hieße anders als das Feld; Zugriffe von außen gingen verloren.
  function Prefixed(const AName: string): Boolean;
  begin
    Result := (Length(AName) >= 2) and CharInSet(AName[1], ['F', 'f']) and CharInSet(AName[2], ['A'..'Z']);
  end;

  // Ein Name allein in seiner Zeile, mit Typ, ohne F-Präfix, FName noch frei und end des Typs am Zeilenanfang.
  function Encapsulable(AType, AField: TSyntaxNode): Boolean;
  var
    mName: string;
  begin
    mName := Trim(AField.Name);
    Result := (Pos(',', mName) = 0) and (AField.FindChild(TSyntaxKind.TypeReference) <> nil) and AloneInLine(AField);
    Result := Result and not Prefixed(mName) and not HasMember(AType, FieldNameOf(mName));
    Result := Result and (Trim(Copy(LineOf(AType.EndPos.Line), 1, AType.EndPos.Character - 3)) = '');
  end;

  function IndexOfChild(AParent, AChild: TSyntaxNode): Integer;
  begin
    for Result := 0 to AParent.ChildCount - 1 do
    begin
      if AParent[Result] = AChild then
      begin
        Exit;
      end;
    end;
    Result := -1;
  end;

  // Einziges Mitglied seines Abschnitts: Das Sichtbarkeitswort geht mit.
  function SectionEdits(AType, AField, ASection: TSyntaxNode): TArray<TTextEdit>;
  var
    mPosition: Integer;
    mNext: TSyntaxNode;
  begin
    Result := nil;
    if (ASection = nil) or not AloneInLine(ASection) then
    begin
      Exit;
    end;
    mPosition := IndexOfChild(AType, AField);
    mNext := nil;
    if (mPosition >= 0) and (mPosition < AType.ChildCount - 1) then
    begin
      mNext := AType[mPosition + 1];
    end;
    if (mPosition > 0) and (AType[mPosition - 1] = ASection) and
      ((mNext = nil) or (mNext.Kind = TSyntaxKind.Visibility))
      then
    begin
      Result := [TTextEdit.Create(TTextRange.Create(ASection.StartPos.Line, 0, ASection.StartPos.Line + 1, 0), '')];
    end;
  end;

  // private-Abschnitt mit FName und die Property im alten Abschnitt, vor dem end des Typs.
  function MemberText(const AName, ATypeName, AIndent, AVisibility: string): string;
  var
    mFieldName: string;
  begin
    mFieldName := FieldNameOf(AName);
    Result := AIndent + 'private' + mLineBreak + AIndent + '  ' + mFieldName + ': ' + ATypeName + ';' + mLineBreak +
      AIndent + AVisibility + mLineBreak + AIndent + '  property ' + AName + ': ' + ATypeName + ' read ' + mFieldName +
      ' write ' + mFieldName + ';' + mLineBreak;
  end;

  // FName in private am Ende des Typs, Property im alten Abschnitt; der leere Abschnitt fällt weg.
  function Encapsulate(AType, AField, ASection: TSyntaxNode; const AVisibility: string;
    out AFix: TRuleFix): Boolean;
  var
    mName, mTypeName, mIndent: string;
    mEndLine: Integer;
    mEdits: TArray<TTextEdit>;
  begin
    Result := Encapsulable(AType, AField);
    if not Result then
    begin
      Exit;
    end;
    mName := Trim(AField.Name);
    mTypeName := NodeText(AField.FindChild(TSyntaxKind.TypeReference));
    mEndLine := AType.EndPos.Line;
    mIndent := TTextLines.IndentOf(LineOf(mEndLine));
    mEdits := SectionEdits(AType, AField, ASection);
    mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(AField.StartPos.Line, 0, AField.StartPos.Line + 1, 0), '')];
    mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(mEndLine, 0, mEndLine, 0),
      MemberText(mName, mTypeName, mIndent,
      AVisibility))];
    AFix := TRuleFix.Create(cTexts[TStyleDeclarationsText.Encapsulate].Text, mEdits);
  end;

  // Zählt ein Feld im Abschnitt AVisibility ('' = ohne Sichtbarkeitswort)?
  function FieldCounts(const AVisibility: string; AImplicitCounts: Boolean): Boolean;
  begin
    if AVisibility = '' then
    begin
      Result := AImplicitCounts;
    end
    else
    begin
      Result := MatchText(AVisibility, ['public', 'published']);
    end;
  end;

  function FieldFixes(AType, AField, ASection: TSyntaxNode; const AVisibility, AImplicit: string): TArray<TRuleFix>;
  var
    mFix: TRuleFix;
    mEncapsulated: Boolean;
  begin
    if AVisibility = '' then
    begin
      mEncapsulated := Encapsulate(AType, AField, nil, AImplicit, mFix);
    end
    else
    begin
      mEncapsulated := Encapsulate(AType, AField, ASection, AVisibility, mFix);
    end;
    Result := nil;
    if mEncapsulated then
    begin
      Result := [mFix];
    end;
  end;

  procedure CheckType(AType: TSyntaxNode; AImplicitCounts: Boolean; const AImplicit: string);
  var
    mIndex: Integer;
    mChild, mSection: TSyntaxNode;
    mVisibility, mName: string;
    mFixes: TArray<TRuleFix>;
  begin
    mVisibility := '';
    mSection := nil;
    for mIndex := 0 to AType.ChildCount - 1 do
    begin
      mChild := AType[mIndex];
      if mChild.Kind = TSyntaxKind.Visibility then
      begin
        mVisibility := mChild.Name;
        mSection := mChild;
        Continue;
      end;
      if (mChild.Kind <> TSyntaxKind.Field) or not FieldCounts(mVisibility, AImplicitCounts) then
      begin
        Continue;
      end;
      mFixes := FieldFixes(AType, mChild, mSection, mVisibility, AImplicit);
      for mName in mChild.Name.Split([',']) do
      begin
        AReport.Add(TTextRange.Create(mChild.StartPos, mChild.EndPos),
          cTexts[TStyleDeclarationsText.PublicField].Fmt([Trim(mName)]), mFixes);
      end;
    end;
  end;

  // Abschnitt ohne Sichtbarkeitswort: bei Klassen ohne Vorfahren public, sonst oft Felder des Designers.
  function PlainClass(AClass: TSyntaxNode): Boolean;
  var
    mAncestor: TSyntaxNode;
  begin
    mAncestor := AClass.FindChild(TSyntaxKind.TypeReference);
    Result := (mAncestor = nil) or SameText(NodeText(mAncestor), 'TObject');
  end;

  // Abschnitt, aus dem von außen niemand zugreift (private, protected, strict …).
  function HiddenSection(const AVisibility: string): Boolean;
  begin
    Result := (AVisibility <> '') and not MatchText(AVisibility, ['public', 'published', 'automated']);
  end;

  // Kinder auf den Stapel, rückwärts; Typen in einem verborgenen Abschnitt erben „verborgen“ (TEntry unter
  // protected type ist eine Hilfsklasse, ihre Felder sind von außen nicht erreichbar).
  procedure PushChildren(ANode: TSyntaxNode; AHidden: Boolean; APending: TStack<TSyntaxNode>;
    AHiddenFlags: TStack<Boolean>);
  var
    mIndex: Integer;
    mFlags: TArray<Boolean>;
    mVisibility: string;
  begin
    SetLength(mFlags, ANode.ChildCount);
    mVisibility := '';
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      if ANode[mIndex].Kind = TSyntaxKind.Visibility then
      begin
        mVisibility := ANode[mIndex].Name;
      end;
      mFlags[mIndex] := AHidden or (ANode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType]) and
        HiddenSection(mVisibility);
    end;
    for mIndex := ANode.ChildCount - 1 downto 0 do
    begin
      APending.Push(ANode[mIndex]);
      AHiddenFlags.Push(mFlags[mIndex]);
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mHiddenFlags: TStack<Boolean>;
    mNode: TSyntaxNode;
    mHidden: Boolean;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    mHiddenFlags := TStack<Boolean>.Create;
    try
      mPending.Push(ANode);
      mHiddenFlags.Push(False);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mHidden := mHiddenFlags.Pop;
        case mNode.Kind of
          TSyntaxKind.ClassType:
            if not mHidden then
            begin
              CheckType(mNode, PlainClass(mNode), 'public');
            end;
          TSyntaxKind.RecordType:
            if mIncludeRecords and not mHidden then
            begin
              CheckType(mNode, True, 'public');
            end;
          TSyntaxKind.Block, TSyntaxKind.AsmBlock:
            Continue;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        PushChildren(mNode, mHidden, mPending, mHiddenFlags);
      end;
    finally
      mHiddenFlags.Free;
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mIncludeRecords := TRuleOptions.Bool(AContext.Options, 'includeRecords', False);
  mLines := TTextLines.SplitLines(AContext.Text, mLineBreak);
  Visit(AContext.Tree.Root);
end;

{ TGlobalVariableRule }

function TGlobalVariableRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('global-variable', TRuleSeverity.Hint,
    cTexts[TStyleDeclarationsText.GlobalTitle].Text, True);
end;

procedure TGlobalVariableRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  cFormRoots: array[0..7] of string = ('TForm', 'TCustomForm', 'TFrame', 'TCustomFrame', 'TDataModule',
    'TService', 'TWebModule', 'TCustomDataModule');
var
  mTokens: TArray<TPascalToken>;
  mFormClasses: TArray<string>;
  mIncludeForms: Boolean;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Klasse mit Vorfahren in einer Unit mit Formulardatei bzw. direkter Nachfahre einer bekannten Designerklasse?
  function IsFormClass(ATypeDecl: TSyntaxNode): Boolean;
  var
    mBody, mAncestor: TSyntaxNode;
  begin
    Result := False;
    mBody := ATypeDecl.FindChild(TSyntaxKind.ClassType);
    if mBody = nil then
    begin
      Exit;
    end;
    mAncestor := mBody.FindChild(TSyntaxKind.TypeReference);
    Result := (mAncestor <> nil) and ((AContext.FormText <> '') or MatchText(NodeText(mAncestor), cFormRoots));
  end;

  // Klassen der Unit, die ein Formular, Frame oder Datenmodul sind: mit Formulardatei jede Klasse mit
  // Vorfahren, sonst die direkten Nachfahren bekannter Designerklassen.
  procedure CollectForms(ANode: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.TypeDecl then
        begin
          if IsFormClass(mNode) then
          begin
            mFormClasses := mFormClasses + [mNode.Name];
          end;
          Continue;
        end;
        if mNode.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.RoutineDecl] then
        begin
          Continue;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  function NameRange(ADecl: TSyntaxNode; const AName: string): TTextRange;
  var
    mIndex: Integer;
  begin
    Result := TTextRange.Create(ADecl.StartPos, ADecl.EndPos);
    // Nur die Token der Deklaration, binär angesprungen statt die ganze Datei (#1342).
    mIndex := TSyntaxTree.FirstTokenOf(mTokens, ADecl.StartOffset);
    while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < ADecl.EndOffset) do
    begin
      if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mIndex].Text, AName) then
      begin
        Exit(TTextRange.Create(mTokens[mIndex].StartPos, mTokens[mIndex].EndPos));
      end;
      Inc(mIndex);
    end;
  end;

  procedure CheckSection(ASection: TSyntaxNode);
  var
    mIndex: Integer;
    mDecl, mTypeRef: TSyntaxNode;
    mName: string;
  begin
    for mIndex := 0 to ASection.ChildCount - 1 do
    begin
      mDecl := ASection[mIndex];
      if mDecl.Kind <> TSyntaxKind.VarDecl then
      begin
        Continue;
      end;
      mTypeRef := mDecl.FindChild(TSyntaxKind.TypeReference);
      if not mIncludeForms and (mTypeRef <> nil) and MatchText(NodeText(mTypeRef), mFormClasses) then
      begin
        Continue;
      end;
      for mName in mDecl.Name.Split([',']) do
      begin
        AReport.Add(NameRange(mDecl, Trim(mName)), cTexts[TStyleDeclarationsText.Global].Fmt([Trim(mName)]));
      end;
    end;
  end;

var
  mInterfacePart: TSyntaxNode;
  mIndex: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mInterfacePart := AContext.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  if mInterfacePart = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mIncludeForms := TRuleOptions.Bool(AContext.Options, 'includeFormVariables', False);
  mFormClasses := nil;
  CollectForms(mInterfacePart);
  for mIndex := 0 to mInterfacePart.ChildCount - 1 do
  begin
    if mInterfacePart[mIndex].Kind = TSyntaxKind.VarSection then
    begin
      CheckSection(mInterfacePart[mIndex]);
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Style.Declarations', cTexts);

end.
