unit Atlas.Common.Editing.DeclarationCommands;

// Schnellbefehle für Deklarationen (#294) im Rahmen aus #293:
//   /var Name: Typ        lokale Variable (legt "var" vor begin an)
//   /var Name := Ausdruck Inline-Variable an der Stelle
//   /const Name = Wert    lokale Konstante; /const! in die implementation
//   /field Name: Typ      Feld FName im private-Abschnitt der Klasse
//   /prop Name: Typ [ro]  Feld, Property und Setter samt Rumpf
//   /resstr               String-Literal der vorigen Zeile als resourcestring
//   /guid                 ['{…}'] in der Interface-Deklaration
//
// Text und Baum liest TCommandSource (Befehlszeile als Leerzeichen).

interface

uses
  Atlas.Common.Editing.Contract;

/// <summary>Trägt die Deklarationsbefehle über ARegister ein.</summary>
procedure RegisterDeclarationCommands(const ARegister: TSlashRegister);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Editing.ClassMembers,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Editing.ResourceStrings,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDeclarationCommandsText = (ExpectedIsVarNameExpression, InlineVariablesExistOnlyFrom, VarOnlyAppliesInThe,
    ExpectedIsVarNameType, ExpectedIsConstNameValue, ConstOnlyAppliesInThe, ConstNeedsAnImplementationSection,
    ExpectedIsFieldNameType, FieldOnlyAppliesInA, ExpectedIsPropNameType, PropOnlyAppliesInA,
    ResstrNeedsAStringLiteral, ResstrNeedsAnImplementationSection, GuidOnlyAppliesInThe, TheInterfaceAlreadyHasA,
    CreateAConstantInThe, CreateAPropertyWithField, StringLiteralAboveAsResourcestring, InsertAGUIDIntoThe,
    CreateALocalVariable, VarListTStringList, CreateALocalConstant, CreateAFieldInThe);

const
  cTexts: array[TDeclarationCommandsText] of TAtlasText = (
    (De: 'Erwartet wird /var Name := Ausdruck'; En: 'Expected is /var Name := Expression'),
    (De: 'Inline-Variablen gibt es erst ab Delphi 10.3 (eingestellt: %s); /var Name: Typ legt eine lokale Variable an';
     En: 'Inline variables exist only from Delphi 10.3 on (set: %s); /var Name: Type creates a local variable'),
    (De: '/var gilt nur im Rumpf einer Routine'; En: '/var only applies in the body of a routine'),
    (De: 'Erwartet wird /var Name: Typ'; En: 'Expected is /var Name: Type'),
    (De: 'Erwartet wird /const Name = Wert'; En: 'Expected is /const Name = Value'),
    (De: '/const gilt nur im Rumpf einer Routine; /const! schreibt in die implementation';
     En: '/const only applies in the body of a routine; /const! writes into the implementation'),
    (De: '/const! braucht einen implementation-Abschnitt'; En: '/const! needs an implementation section'),
    (De: 'Erwartet wird /field Name: Typ'; En: 'Expected is /field Name: Type'),
    (De: '/field gilt nur in einer Klasse oder einer ihrer Methoden';
     En: '/field only applies in a class or one of its methods'),
    (De: 'Erwartet wird /prop Name: Typ [ro]'; En: 'Expected is /prop Name: Type [ro]'),
    (De: '/prop gilt nur in einer Klasse oder einer ihrer Methoden';
     En: '/prop only applies in a class or one of its methods'),
    (De: '/resstr braucht ein String-Literal in der Zeile darüber';
     En: '/resstr needs a string literal in the line above'),
    (De: '/resstr braucht einen implementation-Abschnitt'; En: '/resstr needs an implementation section'),
    (De: '/guid gilt nur in der Deklaration eines Interfaces';
     En: '/guid only applies in the declaration of an interface'),
    (De: 'Das Interface hat schon eine GUID'; En: 'The interface already has a GUID'),
    (De: 'Konstante in der implementation anlegen'; En: 'Create a constant in the implementation'),
    (De: 'Property mit Feld und Setter anlegen'; En: 'Create a property with field and setter'),
    (De: 'String-Literal darüber als resourcestring'; En: 'String literal above as resourcestring'),
    (De: 'GUID in die Interface-Deklaration einfügen'; En: 'Insert a GUID into the interface declaration'),
    (De: 'Lokale Variable anlegen'; En: 'Create a local variable'),
    (De: '/var Liste: TStringList'; En: '/var List: TStringList'),
    (De: 'Lokale Konstante anlegen'; En: 'Create a local constant'),
    (De: 'Feld im private-Abschnitt anlegen'; En: 'Create a field in the private section'));

{$SCOPEDENUMS OFF}

{ /var und /const }

/// <summary>/var Name := Ausdruck: Inline-Variable (ab Delphi 10.3) an der Stelle der Befehlszeile.</summary>
function InlineVarEdit(ASource: TCommandSource; const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mName, mValue: string;
  mAssign: Integer;
begin
  AEdits := nil;
  mAssign := Pos(':=', AContext.Arguments);
  mName := Trim(Copy(AContext.Arguments, 1, mAssign - 1));
  mValue := Trim(Copy(AContext.Arguments, mAssign + 2, MaxInt));
  if mValue.EndsWith(';') then
  begin
    mValue := Trim(Copy(mValue, 1, Length(mValue) - 1));
  end;
  if (mName = '') or (mValue = '') then
  begin
    Exit(Fail(cTexts[TDeclarationCommandsText.ExpectedIsVarNameExpression].Text, AReason));
  end;
  if not TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, AContext.DelphiVersion) then
  begin
    Exit(Fail(cTexts[TDeclarationCommandsText.InlineVariablesExistOnlyFrom].Fmt([AContext.DelphiVersion]), AReason));
  end;
  AEdits := [TTextEdit.Create(TTextRange.Create(ASource.Line, 0, ASource.Line, Length(AContext.LineText)),
    Copy(AContext.LineText, 1, Pos('/', AContext.LineText) - 1) + Format('var %s := %s;', [mName, mValue]))];
  Result := True;
end;

function ExecuteVar(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mRoutine: TSyntaxNode;
  mName, mValue: string;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    mRoutine := mSource.RoutineAt;
    if mRoutine = nil then
    begin
      Exit(Fail(cTexts[TDeclarationCommandsText.VarOnlyAppliesInThe].Text, AReason));
    end;
    if Pos(':=', AContext.Arguments) > 0 then
    begin
      Exit(InlineVarEdit(mSource, AContext, AEdits, AReason));
    end;
    if not SplitDeclaration(AContext.Arguments, ':', mName, mValue) then
    begin
      Exit(Fail(cTexts[TDeclarationCommandsText.ExpectedIsVarNameType].Text, AReason));
    end;
    AEdits := [AddLocal(mSource, mRoutine, TSyntaxKind.VarSection, 'var', Format('%s: %s;', [mName, mValue])),
      mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
  end;
end;

function ExecuteConst(const AContext: TSlashContext; AGlobal: Boolean; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mRoutine, mSection, mNode: TSyntaxNode;
  mName, mValue, mDeclaration: string;
  mIndex: Integer;
begin
  AEdits := nil;
  if not SplitDeclaration(AContext.Arguments, '=', mName, mValue) then
  begin
    Exit(Fail(cTexts[TDeclarationCommandsText.ExpectedIsConstNameValue].Text, AReason));
  end;
  mDeclaration := Format('%s = %s;', [mName, mValue]);
  mSource := TCommandSource.Create(AContext);
  try
    if not AGlobal then
    begin
      mRoutine := mSource.RoutineAt;
      if mRoutine = nil then
      begin
        Exit(Fail(cTexts[TDeclarationCommandsText.ConstOnlyAppliesInThe].Text, AReason));
      end;
      AEdits := [AddLocal(mSource, mRoutine, TSyntaxKind.ConstSection, 'const', mDeclaration), mSource.RemoveCommand];
      Exit(True);
    end;
    if mSource.ImplementationStart < 0 then
    begin
      Exit(Fail(cTexts[TDeclarationCommandsText.ConstNeedsAnImplementationSection].Text, AReason));
    end;
    // Erster const-Abschnitt direkt in der implementation, sonst ein neuer hinter uses.
    mSection := mSource.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
    mNode := nil;
    for mIndex := 0 to mSection.ChildCount - 1 do
    begin
      if (mSection[mIndex].Kind = TSyntaxKind.ConstSection) and (mNode = nil) then
      begin
        mNode := mSection[mIndex];
      end;
    end;
    if mNode <> nil then
    begin
      AEdits := [mSource.AfterLine(mNode.EndPos.Line, '  ' + mDeclaration)];
    end
    else
    begin
      AEdits := [mSource.AfterLine(mSource.ImplementationStart, mSource.LineBreak + 'const' + mSource.LineBreak + '  ' +
        mDeclaration)];
    end;
    AEdits := AEdits + [mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /field und /prop }

function ExecuteField(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mClassSymbol: TIndexSymbol;
  mName, mTypeName, mIndent: string;
  mLine: Integer;
begin
  AEdits := nil;
  if not SplitDeclaration(AContext.Arguments, ':', mName, mTypeName) then
  begin
    Exit(Fail(cTexts[TDeclarationCommandsText.ExpectedIsFieldNameType].Text, AReason));
  end;
  if not StartsText('F', mName) or (Length(mName) < 2) or not CharInSet(mName[2], ['A'..'Z']) then
  begin
    mName := 'F' + UpperCase(Copy(mName, 1, 1)) + Copy(mName, 2, MaxInt);
  end;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClassSymbol) then
    begin
      Exit(Fail(cTexts[TDeclarationCommandsText.FieldOnlyAppliesInA].Text, AReason));
    end;
    mLine := mSource.PrivateLine(mClassSymbol);
    if mLine >= 0 then
    begin
      AEdits := [mSource.AfterLine(mLine, mSource.Indent(mLine) + '  ' + Format('%s: %s;', [mName, mTypeName]))];
    end
    else
    begin
      mIndent := mSource.Indent(mClassSymbol.Range.EndPos.Line);
      AEdits := [mSource.BeforeLine(mClassSymbol.Range.EndPos.Line, mIndent + 'private' + mSource.LineBreak + mIndent +
        '  ' + Format('%s: %s;', [mName, mTypeName]))];
    end;
    AEdits := AEdits + [mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
  end;
end;

type
  /// <summary>Property von /prop: Name, Typ und ob sie nur lesbar ist.</summary>
  TPropSpec = record
    Name: string;
    TypeName: string;
    ReadOnly: Boolean;
    function Field: string;
    function Setter: string;
    function Declarations(const AIndent, ALineBreak: string; AHasPrivate: Boolean): string;
  end;

/// <summary>"/prop Name: Typ [ro]" zerlegen; False bei falscher Form.</summary>
function ParsePropArguments(const AArguments: string; out ASpec: TPropSpec): Boolean;
var
  mArguments: string;
begin
  ASpec := Default(TPropSpec);
  mArguments := Trim(AArguments);
  ASpec.ReadOnly := EndsText(' ro', mArguments);
  if ASpec.ReadOnly then
  begin
    mArguments := Trim(Copy(mArguments, 1, Length(mArguments) - 3));
  end;
  Result := SplitDeclaration(mArguments, ':', ASpec.Name, ASpec.TypeName);
end;

function TPropSpec.Field: string;
begin
  Result := 'F' + Name;
end;

function TPropSpec.Setter: string;
begin
  Result := 'Set' + Name;
end;

/// <summary>Abschnitte vor "end": das Feld in private, wenn es noch keinen private-Abschnitt gibt (AHasPrivate),
/// der Setter in private und die Property in public.</summary>
function TPropSpec.Declarations(const AIndent, ALineBreak: string; AHasPrivate: Boolean): string;
begin
  Result := '';
  if not AHasPrivate then
  begin
    Result := AIndent + 'private' + ALineBreak + AIndent + '  ' + Format('%s: %s;', [Field, TypeName]) + ALineBreak;
  end;
  if not ReadOnly then
  begin
    if AHasPrivate then
    begin
      Result := Result + AIndent + 'private' + ALineBreak;
    end;
    Result := Result + AIndent + '  ' + Format('procedure %s(const Value: %s);', [Setter, TypeName]) + ALineBreak;
  end;
  Result := Result + AIndent + 'public' + ALineBreak + AIndent + '  ';
  if ReadOnly then
  begin
    Result := Result + Format('property %s: %s read %s;', [Name, TypeName, Field]);
  end
  else
  begin
    Result := Result + Format('property %s: %s read %s write %s;', [Name, TypeName, Field, Setter]);
  end;
end;

function ExecuteProp(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mClass: TIndexSymbol;
  mSpec: TPropSpec;
  mLB: string;
  mLine, mEndLine: Integer;
begin
  AEdits := nil;
  if not ParsePropArguments(AContext.Arguments, mSpec) then
  begin
    Exit(Fail(cTexts[TDeclarationCommandsText.ExpectedIsPropNameType].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClass) then
    begin
      Exit(Fail(cTexts[TDeclarationCommandsText.PropOnlyAppliesInA].Text, AReason));
    end;
    mLB := mSource.LineBreak;
    mEndLine := mClass.Range.EndPos.Line;
    // Feld oben in private, Setter und Property in eigenen Abschnitten vor "end":
    // Felder müssen in einem Abschnitt vor den Methoden stehen.
    mLine := mSource.PrivateLine(mClass);
    if mLine >= 0 then
    begin
      AEdits := [mSource.AfterLine(mLine, mSource.Indent(mLine) + '  ' + Format('%s: %s;', [mSpec.Field,
        mSpec.TypeName]))];
    end;
    AEdits := AEdits + [mSource.BeforeLine(mEndLine, mSpec.Declarations(mSource.Indent(mEndLine), mLB,
      mLine >= 0))];
    if not mSpec.ReadOnly then
    begin
      // Derselbe Setter wie bei /changed und der Code-Vorlage (#51): nur bei Änderung, mit Benachrichtigung.
      AEdits := AEdits + [mSource.AddBody(mClass.Name, Format('procedure %s.%s(const Value: %s);', [mClass.Name,
        mSpec.Setter, mSpec.TypeName]) + mLB + TSetterGenerator.Body(mSpec.Field, 'Value',
        TSetterGenerator.NotifyCall(mSource, AContext.Index, mClass), mLB))];
    end;
    AEdits := AEdits + [mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /resstr }

/// <summary>Erstes String-Literal in der Zeile über der Befehlszeile.</summary>
function LiteralAbove(ASource: TCommandSource; out ALiteral: TPascalToken): Boolean;
var
  mToken: TPascalToken;
begin
  ALiteral := Default(TPascalToken);
  for mToken in ASource.Tree.Tokens do
  begin
    if (mToken.Kind = TPascalTokenKind.StringLiteral) and (mToken.StartPos.Line = ASource.Line - 1) then
    begin
      ALiteral := mToken;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Letzte Zeile des ersten resourcestring-Abschnitts zwischen AStart und der Befehlszeile; -1 ohne.
/// </summary>
function ResourceSectionEnd(ASource: TCommandSource; AStart: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := AStart + 1 to ASource.Line - 1 do
  begin
    if SameText(Trim(ASource.Lines[mIndex]), 'resourcestring') then
    begin
      Result := mIndex;
      while (Result + 1 < ASource.Line) and (Pos('=', ASource.Lines[Result + 1]) > 0) and
        (Trim(ASource.Lines[Result + 1]) <> '') do
      begin
        Inc(Result);
      end;
      Exit;
    end;
  end;
  Result := -1;
end;

/// <summary>Name aus den Argumenten, sonst aus dem Text des Literals AValue.</summary>
function ResourceName(const AArguments, AValue: string): string;
begin
  Result := AArguments;
  if not IsValidIdent(Result) then
  begin
    Result := TResourceStrings.NameFor(StringReplace(Copy(AValue, 2, Length(AValue) - 2), '''''', '''',
      [rfReplaceAll]));
  end;
end;

function ExecuteResStr(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mLiteral: TPascalToken;
  mName, mValue: string;
  mStart, mLast: Integer;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if not LiteralAbove(mSource, mLiteral) then
    begin
      Exit(Fail(cTexts[TDeclarationCommandsText.ResstrNeedsAStringLiteral].Text, AReason));
    end;
    mStart := mSource.ImplementationStart;
    if mStart < 0 then
    begin
      Exit(Fail(cTexts[TDeclarationCommandsText.ResstrNeedsAnImplementationSection].Text, AReason));
    end;
    mValue := mLiteral.Text;
    mName := ResourceName(AContext.Arguments, mValue);
    // Vorhandener resourcestring-Abschnitt hinter implementation: dort anhängen.
    mLast := ResourceSectionEnd(mSource, mStart);
    if mLast >= 0 then
    begin
      AEdits := [mSource.AfterLine(mLast, Format('  %s = %s;', [mName, mValue]))];
    end
    else
    begin
      AEdits := [mSource.AfterLine(mStart, mSource.LineBreak + 'resourcestring' + mSource.LineBreak +
        Format('  %s = %s;', [mName, mValue]))];
    end;
    AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(mLiteral.StartPos, mLiteral.EndPos), mName),
      mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /guid }

function ExecuteGuid(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mSymbol, mTarget: TIndexSymbol;
  mFound: Boolean;
  mIndex: Integer;
  mGuid: TGUID;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    mFound := False;
    mTarget := Default(TIndexSymbol);
    for mSymbol in mSource.UnitIndex.Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.InterfaceType) and (mSymbol.Range.StartPos.Line < mSource.Line) and
        (mSymbol.Range.EndPos.Line >= mSource.Line) then
      begin
        mTarget := mSymbol;
        mFound := True;
        Break;
      end;
    end;
    if not mFound then
    begin
      Exit(Fail(cTexts[TDeclarationCommandsText.GuidOnlyAppliesInThe].Text, AReason));
    end;
    for mIndex := mTarget.Range.StartPos.Line to mTarget.Range.EndPos.Line do
    begin
      if StartsStr('[''{', Trim(mSource.Lines[mIndex])) then
      begin
        Exit(Fail(cTexts[TDeclarationCommandsText.TheInterfaceAlreadyHasA].Text, AReason));
      end;
    end;
    CreateGUID(mGuid);
    AEdits := [TTextEdit.Create(TTextRange.Create(mSource.Line, 0, mSource.Line, Length(AContext.LineText)),
      Copy(AContext.LineText, 1, Pos('/', AContext.LineText) - 1) + Format('[''%s'']', [GUIDToString(mGuid)]))];
    Result := True;
  finally
    mSource.Free;
  end;
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterDeclarationCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('var', cTexts[TDeclarationCommandsText.CreateALocalVariable].Text,
    cTexts[TDeclarationCommandsText.VarListTStringList].Text, ExecuteVar));
  ARegister(Command('const', cTexts[TDeclarationCommandsText.CreateALocalConstant].Text, '/const Max = 10',
    function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteConst(AContext, False, AEdits, AReason);
    end));
  ARegister(Command('const!', cTexts[TDeclarationCommandsText.CreateAConstantInThe].Text, '/const! Max = 10',
    function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteConst(AContext, True, AEdits, AReason);
    end));
  ARegister(Command('field', cTexts[TDeclarationCommandsText.CreateAFieldInThe].Text, '/field Name: string',
    ExecuteField));
  ARegister(Command('prop', cTexts[TDeclarationCommandsText.CreateAPropertyWithField].Text, '/prop Name: string',
    ExecuteProp));
  ARegister(Command('resstr', cTexts[TDeclarationCommandsText.StringLiteralAboveAsResourcestring].Text, '/resstr',
    ExecuteResStr));
  ARegister(Command('guid', cTexts[TDeclarationCommandsText.InsertAGUIDIntoThe].Text, '/guid', ExecuteGuid));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.DeclarationCommands', cTexts);

end.
