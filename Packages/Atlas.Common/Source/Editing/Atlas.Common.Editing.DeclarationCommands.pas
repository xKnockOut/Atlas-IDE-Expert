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
  Atlas.Common.Editing.ResourceStrings;

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
    Exit(Fail('Erwartet wird /var Name := Ausdruck', AReason));
  end;
  if not TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, AContext.DelphiVersion) then
  begin
    Exit(Fail(Format('Inline-Variablen gibt es erst ab Delphi 10.3 (eingestellt: %s); /var Name: Typ legt ' +
      'eine lokale Variable an', [AContext.DelphiVersion]), AReason));
  end;
  AEdits := [TTextEdit.Create(TTextRange.Create(ASource.Line, 0, ASource.Line, Length(AContext.LineText)),
    Copy(AContext.LineText, 1, Pos('/', AContext.LineText) - 1) + Format('var %s := %s;', [mName, mValue]))];
  Result := True;
end;

function ExecuteVar(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Name, Value: string;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Routine := Source.RoutineAt;
    if Routine = nil then
    begin
      Exit(Fail('/var gilt nur im Rumpf einer Routine', AReason));
    end;
    if Pos(':=', AContext.Arguments) > 0 then
    begin
      Exit(InlineVarEdit(Source, AContext, AEdits, AReason));
    end;
    if not SplitDeclaration(AContext.Arguments, ':', Name, Value) then
    begin
      Exit(Fail('Erwartet wird /var Name: Typ', AReason));
    end;
    AEdits := [AddLocal(Source, Routine, TSyntaxKind.VarSection, 'var', Format('%s: %s;', [Name, Value])),
      Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

function ExecuteConst(const AContext: TSlashContext; AGlobal: Boolean; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine, Section, Node: TSyntaxNode;
  Name, Value, Declaration: string;
  Index: Integer;
begin
  AEdits := nil;
  if not SplitDeclaration(AContext.Arguments, '=', Name, Value) then
  begin
    Exit(Fail('Erwartet wird /const Name = Wert', AReason));
  end;
  Declaration := Format('%s = %s;', [Name, Value]);
  Source := TCommandSource.Create(AContext);
  try
    if not AGlobal then
    begin
      Routine := Source.RoutineAt;
      if Routine = nil then
      begin
        Exit(Fail('/const gilt nur im Rumpf einer Routine; /const! schreibt in die implementation', AReason));
      end;
      AEdits := [AddLocal(Source, Routine, TSyntaxKind.ConstSection, 'const', Declaration), Source.RemoveCommand];
      Exit(True);
    end;
    if Source.ImplementationStart < 0 then
    begin
      Exit(Fail('/const! braucht einen implementation-Abschnitt', AReason));
    end;
    // Erster const-Abschnitt direkt in der implementation, sonst ein neuer hinter uses.
    Section := Source.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
    Node := nil;
    for Index := 0 to Section.ChildCount - 1 do
    begin
      if (Section[Index].Kind = TSyntaxKind.ConstSection) and (Node = nil) then
      begin
        Node := Section[Index];
      end;
    end;
    if Node <> nil then
    begin
      AEdits := [Source.AfterLine(Node.EndPos.Line, '  ' + Declaration)];
    end
    else
    begin
      AEdits := [Source.AfterLine(Source.ImplementationStart, Source.LineBreak + 'const' + Source.LineBreak + '  ' +
        Declaration)];
    end;
    AEdits := AEdits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /field und /prop }

function ExecuteField(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Name, TypeName, Indent: string;
  Line: Integer;
begin
  AEdits := nil;
  if not SplitDeclaration(AContext.Arguments, ':', Name, TypeName) then
  begin
    Exit(Fail('Erwartet wird /field Name: Typ', AReason));
  end;
  if not StartsText('F', Name) or (Length(Name) < 2) or not CharInSet(Name[2], ['A'..'Z']) then
  begin
    Name := 'F' + UpperCase(Copy(Name, 1, 1)) + Copy(Name, 2, MaxInt);
  end;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
    begin
      Exit(Fail('/field gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    end;
    Line := Source.PrivateLine(ClassSymbol);
    if Line >= 0 then
    begin
      AEdits := [Source.AfterLine(Line, Source.Indent(Line) + '  ' + Format('%s: %s;', [Name, TypeName]))];
    end
    else
    begin
      Indent := Source.Indent(ClassSymbol.Range.EndPos.Line);
      AEdits := [Source.BeforeLine(ClassSymbol.Range.EndPos.Line, Indent + 'private' + Source.LineBreak + Indent +
        '  ' + Format('%s: %s;', [Name, TypeName]))];
    end;
    AEdits := AEdits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
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
    Exit(Fail('Erwartet wird /prop Name: Typ [ro]', AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClass) then
    begin
      Exit(Fail('/prop gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
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
      Exit(Fail('/resstr braucht ein String-Literal in der Zeile darüber', AReason));
    end;
    mStart := mSource.ImplementationStart;
    if mStart < 0 then
    begin
      Exit(Fail('/resstr braucht einen implementation-Abschnitt', AReason));
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
  Source: TCommandSource;
  Symbol, Target: TIndexSymbol;
  Found: Boolean;
  Index: Integer;
  Guid: TGUID;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Found := False;
    Target := Default(TIndexSymbol);
    for Symbol in Source.UnitIndex.Symbols do
    begin
      if (Symbol.Kind = TIndexSymbolKind.InterfaceType) and (Symbol.Range.StartPos.Line < Source.Line) and
        (Symbol.Range.EndPos.Line >= Source.Line) then
      begin
        Target := Symbol;
        Found := True;
        Break;
      end;
    end;
    if not Found then
    begin
      Exit(Fail('/guid gilt nur in der Deklaration eines Interfaces', AReason));
    end;
    for Index := Target.Range.StartPos.Line to Target.Range.EndPos.Line do
    begin
      if StartsStr('[''{', Trim(Source.Lines[Index])) then
      begin
        Exit(Fail('Das Interface hat schon eine GUID', AReason));
      end;
    end;
    CreateGUID(Guid);
    AEdits := [TTextEdit.Create(TTextRange.Create(Source.Line, 0, Source.Line, Length(AContext.LineText)),
      Copy(AContext.LineText, 1, Pos('/', AContext.LineText) - 1) + Format('[''%s'']', [GUIDToString(Guid)]))];
    Result := True;
  finally
    Source.Free;
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
  ARegister(Command('var', 'Lokale Variable anlegen', '/var Liste: TStringList', ExecuteVar));
  ARegister(Command('const', 'Lokale Konstante anlegen', '/const Max = 10',
    function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteConst(AContext, False, AEdits, AReason);
    end));
  ARegister(Command('const!', 'Konstante in der implementation anlegen', '/const! Max = 10',
    function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteConst(AContext, True, AEdits, AReason);
    end));
  ARegister(Command('field', 'Feld im private-Abschnitt anlegen', '/field Name: string', ExecuteField));
  ARegister(Command('prop', 'Property mit Feld und Setter anlegen', '/prop Name: string', ExecuteProp));
  ARegister(Command('resstr', 'String-Literal darüber als resourcestring', '/resstr', ExecuteResStr));
  ARegister(Command('guid', 'GUID in die Interface-Deklaration einfügen', '/guid', ExecuteGuid));
end;

end.
