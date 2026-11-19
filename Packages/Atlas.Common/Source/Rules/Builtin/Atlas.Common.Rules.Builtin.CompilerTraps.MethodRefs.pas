unit Atlas.Common.Rules.Builtin.CompilerTraps.MethodRefs;

// Methodenreferenzen, die Delphi aufruft, wo Free Pascal sie als Wert nimmt (#1899, #1345, Gruppe Compiler vorab):
//   method-reference-called  Eine Variable, ein Parameter oder ein Feld vom Typ einer Referenz auf eine Funktion
//                            (TFunc<…>, TPredicate<T>, eigener reference to function) steht als einziges Argument in
//                            Exit(…) oder als Element eines Array-Literals neben + (FListe + [ARef]). Delphi ruft die
//                            Referenz dort auf, statt sie als Wert zu nehmen (wie E2035 bzw. E2010). Korrektur bei
//                            Exit (sicher): Result := ARef; Exit;. Beim Array-Literal: SetLength und zuweisen.
//                            Erkannt wird der Typ aus der Deklaration in der Datei (Parameter, lokale Variable, Feld
//                            der eigenen Klasse); ein eigener Typ zählt, wenn die Datei oder der Index ihn als
//                            reference to function deklariert. Referenzen auf Prozeduren (TProc) nimmt Delphi als
//                            Wert (Links + [AAction] übersetzt).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cMethodReferenceCalledRuleId = 'method-reference-called';

type
  TMethodReferenceCalledRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Meldet die Regel in ARegistry an.</summary>
procedure RegisterCompilerTrapMethodRefRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor.TypeText,
  Atlas.Common.Semantics.RtlMethodReferences,
  Atlas.Common.Rules.Builtin.CompilerTraps,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TMethodRefText = (Title, ExitMessage, ExitFix, LiteralMessage);

  /// <summary>Art eines Typs: keine Methodenreferenz, Referenz auf eine Prozedur oder auf eine Funktion.</summary>
  TReferenceKind = (None, Procedure_, Function_);

const
  cTexts: array[TMethodRefText] of TAtlasText = (
    (De: 'Methodenreferenz wird aufgerufen statt übergeben'; En: 'Method reference is called instead of passed'),
    (De: 'Exit(%s): %0:s ist eine Methodenreferenz (%s); Delphi ruft sie hier auf, statt sie zurückzugeben (wie ' +
      'E2035 bzw. E2010). Result := %0:s; Exit; schreiben.';
     En: 'Exit(%s): %0:s is a method reference (%s); Delphi calls it here instead of returning it (like E2035 or ' +
      'E2010). Write Result := %0:s; Exit;.'),
    (De: 'Result := %s; Exit; schreiben'; En: 'Write Result := %s; Exit;'),
    (De: '[%s]: %0:s ist eine Methodenreferenz (%s); im Array-Literal neben + ruft Delphi sie auf (wie E2035 bzw. ' +
      'E2010). Länge mit SetLength erhöhen und das Element zuweisen.';
     En: '[%s]: %0:s is a method reference (%s); in an array literal next to + Delphi calls it (like E2035 or ' +
      'E2010). Grow the array with SetLength and assign the element.'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Sucht Methodenreferenzen, die Delphi aufruft, in einer Datei.</summary>
  TMethodRefScan = class
  private
    FText: string;
    FRoot: TSyntaxNode;
    FIndex: ISymbolIndex;
    FReport: IRuleReport;
    /// <summary>Ergebnis von KindOf je Typtext (klein).</summary>
    FKnown: TDictionary<string, TReferenceKind>;
    function DeclaredInFile(const AName: string; out AKind: TReferenceKind): Boolean;
    function DeclaredInIndex(const AName: string; out AKind: TReferenceKind): Boolean;
    function KindOf(const ATypeText: string): TReferenceKind;
    function IsReferenceType(const ATypeText: string): Boolean;
    /// <summary>Nur Referenzen auf Funktionen ruft Delphi als Wert auf; TProc neben + nimmt es als Element.</summary>
    function IsFunctionReference(const ATypeText: string): Boolean;
    function TypeOfName(ANode: TSyntaxNode; const AName: string): string;
    function TypeInRoutine(ARoutine: TSyntaxNode; const AKey: string): string;
    function TypeInClass(const AClassName, AKey: string): string;
    function ResultIsReference(ACall: TSyntaxNode): Boolean;
    function ElementType(AOperand: TSyntaxNode): string;
    procedure CheckExit(ACall: TSyntaxNode);
    procedure CheckLiteral(ALiteral: TSyntaxNode);
  public
    constructor Create(const AText: string; ARoot: TSyntaxNode; const AIndex: ISymbolIndex;
      const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

/// <summary>Enthält die Namensliste AList ("A, B") den Namen mit dem Schlüssel AKey (klein)?</summary>
function ListHas(const AList, AKey: string): Boolean;
var
  mName: string;
begin
  for mName in AList.Split([',']) do
  begin
    if SameText(Trim(mName), AKey) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Typtext der Deklaration ANode (Parameter, Variable, Feld); '' ohne.</summary>
function DeclaredTypeText(ANode: TSyntaxNode): string;
var
  mType: TSyntaxNode;
begin
  Result := '';
  mType := TIndexTypeText.DeclaredTypeNode(ANode);
  if (mType <> nil) and (mType.Kind = TSyntaxKind.TypeReference) then
  begin
    Result := TIndexTypeText.TypeText(mType);
  end;
end;

{ TMethodRefScan }

constructor TMethodRefScan.Create(const AText: string; ARoot: TSyntaxNode; const AIndex: ISymbolIndex;
  const AReport: IRuleReport);
begin
  inherited Create;
  FText := AText;
  FRoot := ARoot;
  FIndex := AIndex;
  FReport := AReport;
  FKnown := TDictionary<string, TReferenceKind>.Create;
end;

destructor TMethodRefScan.Destroy;
begin
  FKnown.Free;
  inherited;
end;

/// <summary>Art der Methodenreferenz AProc (ProcedureType "reference"): mit Ergebnistyp eine Funktion.</summary>
function KindOfProcedureType(AProc: TSyntaxNode): TReferenceKind;
begin
  Result := TReferenceKind.None;
  if (AProc <> nil) and SameText(AProc.Name, 'reference') then
  begin
    Result := TReferenceKind.Procedure_;
    if AProc.FindChild(TSyntaxKind.TypeReference) <> nil then
    begin
      Result := TReferenceKind.Function_;
    end;
  end;
end;

function TMethodRefScan.DeclaredInFile(const AName: string; out AKind: TReferenceKind): Boolean;
var
  mFound: Boolean;
  mKind: TReferenceKind;
begin
  mFound := False;
  mKind := TReferenceKind.None;
  FRoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := not mFound;
      if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, AName) then
      begin
        mFound := True;
        mKind := KindOfProcedureType(ANode.FindChild(TSyntaxKind.ProcedureType));
      end;
    end);
  AKind := mKind;
  Result := mFound;
end;

function TMethodRefScan.DeclaredInIndex(const AName: string; out AKind: TReferenceKind): Boolean;
var
  mLocation: TSymbolLocation;
  mSeen: Boolean;
begin
  Result := False;
  mSeen := False;
  AKind := TReferenceKind.Function_;
  if FIndex = nil then
  begin
    Exit;
  end;
  for mLocation in FIndex.FindSymbols(AName) do
  begin
    if mLocation.Symbol.Kind = TIndexSymbolKind.TypeAlias then
    begin
      // Mehrere gleichnamige Typen: nur, wenn alle Methodenreferenzen sind.
      if not ContainsText(mLocation.Symbol.Signature, 'reference to') then
      begin
        Exit(False);
      end;
      // Eine Prozedur unter den gleichnamigen genügt: dann nicht als Funktion melden.
      if not ContainsText(mLocation.Symbol.Signature, 'reference to function') then
      begin
        AKind := TReferenceKind.Procedure_;
      end;
      mSeen := True;
    end;
  end;
  Result := mSeen;
end;

function TMethodRefScan.KindOf(const ATypeText: string): TReferenceKind;
var
  mReference: TRtlMethodReference;
  mBase: string;
  mKind: TReferenceKind;
begin
  if ATypeText = '' then
  begin
    Exit(TReferenceKind.None);
  end;
  if FKnown.TryGetValue(LowerCase(ATypeText), mKind) then
  begin
    Exit(mKind);
  end;
  TRtlMethodReferences.TypeArgs(ATypeText, mBase);
  if not DeclaredInFile(mBase, mKind) and not DeclaredInIndex(mBase, mKind) then
  begin
    mKind := TReferenceKind.None;
    if TRtlMethodReferences.Find(ATypeText, mReference) then
    begin
      mKind := TReferenceKind.Procedure_;
      if ContainsText(mReference.Signature, 'reference to function') then
      begin
        mKind := TReferenceKind.Function_;
      end;
    end;
  end;
  FKnown.Add(LowerCase(ATypeText), mKind);
  Result := mKind;
end;

function TMethodRefScan.IsReferenceType(const ATypeText: string): Boolean;
begin
  Result := KindOf(ATypeText) <> TReferenceKind.None;
end;

function TMethodRefScan.IsFunctionReference(const ATypeText: string): Boolean;
begin
  Result := KindOf(ATypeText) = TReferenceKind.Function_;
end;

function TMethodRefScan.TypeInRoutine(ARoutine: TSyntaxNode; const AKey: string): string;
var
  mType: string;
begin
  mType := '';
  ARoutine.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      // Verschachtelte Routinen haben eigene Namen.
      Result := (mType = '') and ((ANode = ARoutine) or (ANode.Kind <> TSyntaxKind.RoutineDecl));
      if Result and (ANode.Kind in [TSyntaxKind.Parameter, TSyntaxKind.VarDecl, TSyntaxKind.InlineVar]) and
        ListHas(ANode.Name, AKey) then
      begin
        mType := DeclaredTypeText(ANode);
        if mType = '' then
        begin
          // Unbekannter Typ: weiter außen nicht suchen.
          mType := '?';
        end;
      end;
    end);
  Result := mType;
end;

function TMethodRefScan.TypeInClass(const AClassName, AKey: string): string;
var
  mType: string;
begin
  mType := '';
  FRoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mBody: TSyntaxNode;
    begin
      Result := (mType = '') and (ANode.Kind <> TSyntaxKind.RoutineDecl);
      if not Result or (ANode.Kind <> TSyntaxKind.TypeDecl) or not SameText(ANode.Name, AClassName) then
      begin
        Exit;
      end;
      mBody := ANode.FindChild(TSyntaxKind.ClassType);
      if mBody = nil then
      begin
        mBody := ANode.FindChild(TSyntaxKind.RecordType);
      end;
      if mBody = nil then
      begin
        Exit;
      end;
      mBody.Walk(
        function(AMember: TSyntaxNode): Boolean
        begin
          Result := mType = '';
          if Result and (AMember.Kind in [TSyntaxKind.Field, TSyntaxKind.VarDecl]) and ListHas(AMember.Name, AKey) then
          begin
            mType := DeclaredTypeText(AMember);
          end;
        end);
    end);
  Result := mType;
end;

function TMethodRefScan.TypeOfName(ANode: TSyntaxNode; const AName: string): string;
var
  mRoutine: TSyntaxNode;
  mClassName: string;
begin
  Result := '';
  mRoutine := ANode.Parent;
  while mRoutine <> nil do
  begin
    if mRoutine.Kind = TSyntaxKind.AnonymousMethod then
    begin
      // Exit in einer anonymen Methode und deren Namen: nicht verfolgt.
      Exit;
    end;
    if mRoutine.Kind = TSyntaxKind.RoutineDecl then
    begin
      Result := TypeInRoutine(mRoutine, AName);
      if Result <> '' then
      begin
        Break;
      end;
      mClassName := mRoutine.Name;
    end;
    mRoutine := mRoutine.Parent;
  end;
  if (Result = '') and (Pos('.', mClassName) > 0) then
  begin
    mClassName := Copy(mClassName, 1, LastDelimiter('.', mClassName) - 1);
    mClassName := Copy(mClassName, LastDelimiter('.', mClassName) + 1, MaxInt);
    if Pos('<', mClassName) > 0 then
    begin
      mClassName := Copy(mClassName, 1, Pos('<', mClassName) - 1);
    end;
    Result := TypeInClass(mClassName, AName);
  end;
  if Result = '?' then
  begin
    Result := '';
  end;
end;

function TMethodRefScan.ResultIsReference(ACall: TSyntaxNode): Boolean;
var
  mRoutine: TSyntaxNode;
begin
  // Exit(AFunc) in einer Funktion mit anderem Ergebnistyp ruft AFunc gewollt auf.
  mRoutine := EnclosingRoutine(ACall);
  Result := (mRoutine <> nil) and IsReferenceType(ResultTypeText(FText, mRoutine));
end;

function TMethodRefScan.ElementType(AOperand: TSyntaxNode): string;
var
  mType: string;
begin
  Result := '';
  if AOperand.Kind <> TSyntaxKind.Identifier then
  begin
    Exit;
  end;
  mType := StringReplace(TypeOfName(AOperand, AOperand.Name), ' ', '', [rfReplaceAll]);
  if StartsText('TArray<', mType) and EndsStr('>', mType) then
  begin
    Result := Copy(mType, 8, Length(mType) - 8);
  end
  else if StartsText('arrayof', mType) then
  begin
    Result := Copy(mType, 8, MaxInt);
  end;
end;

procedure TMethodRefScan.CheckExit(ACall: TSyntaxNode);
var
  mArgument, mStatement: TSyntaxNode;
  mType, mName, mFixText: string;
  mFix: TRuleFix;
begin
  mArgument := ACall[1];
  mName := mArgument.Name;
  mType := TypeOfName(ACall, mName);
  if not IsFunctionReference(mType) or not ResultIsReference(ACall) then
  begin
    Exit;
  end;
  mStatement := ACall.Parent;
  mFixText := 'Result := ' + mName + '; Exit';
  if (mStatement.Parent = nil) or (mStatement.Parent.Kind <> TSyntaxKind.Block) then
  begin
    mFixText := 'begin ' + mFixText + '; end';
  end;
  mFix := TRuleFix.Create(cTexts[TMethodRefText.ExitFix].Fmt([mName]), [TTextEdit.Create(TTextRange.Create(
    mStatement.StartPos, mStatement.EndPos), mFixText)], True);
  FReport.Add(TTextRange.Create(mArgument.StartPos, mArgument.EndPos), cTexts[TMethodRefText.ExitMessage].Fmt(
    [mName, mType]), TRuleConfidence.High, [mFix]);
end;

procedure TMethodRefScan.CheckLiteral(ALiteral: TSyntaxNode);
var
  mIndex: Integer;
  mElement, mOther: TSyntaxNode;
  mType, mArrayElement: string;
begin
  // Nur neben einem Array, dessen Elemente selbst Methodenreferenzen sind (FListe: TArray<TProc>).
  mOther := ALiteral.Parent[0];
  if mOther = ALiteral then
  begin
    mOther := ALiteral.Parent[1];
  end;
  mArrayElement := ElementType(mOther);
  if not IsReferenceType(mArrayElement) then
  begin
    Exit;
  end;
  for mIndex := 0 to ALiteral.ChildCount - 1 do
  begin
    mElement := ALiteral[mIndex];
    if mElement.Kind <> TSyntaxKind.Identifier then
    begin
      Continue;
    end;
    mType := TypeOfName(ALiteral, mElement.Name);
    if IsFunctionReference(mType) then
    begin
      FReport.Add(TTextRange.Create(mElement.StartPos, mElement.EndPos), cTexts[TMethodRefText.LiteralMessage].Fmt(
        [mElement.Name, mType]), TRuleConfidence.High);
    end;
  end;
end;

/// <summary>Exit(Name) als Anweisung: der Aufruf, sonst nil.</summary>
function ExitWithName(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount = 1) and (ANode[0].Kind = TSyntaxKind.Call) and
    (ANode[0].ChildCount = 2) and (ANode[0][0].Kind = TSyntaxKind.Identifier) and
    SameText(ANode[0][0].Name, 'Exit') and (ANode[0][1].Kind = TSyntaxKind.Identifier) then
  begin
    Result := ANode[0];
  end;
end;

procedure TMethodRefScan.Run;
begin
  FRoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mCall: TSyntaxNode;
      mIndex: Integer;
    begin
      Result := True;
      mCall := ExitWithName(ANode);
      if mCall <> nil then
      begin
        CheckExit(mCall);
      end
      else if (ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.Name = '+') then
      begin
        for mIndex := 0 to ANode.ChildCount - 1 do
        begin
          if ANode[mIndex].Kind = TSyntaxKind.SetConstructor then
          begin
            CheckLiteral(ANode[mIndex]);
          end;
        end;
      end;
    end);
end;

{ TMethodReferenceCalledRule }

function TMethodReferenceCalledRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cMethodReferenceCalledRuleId, TRuleSeverity.Error,
    cTexts[TMethodRefText.Title].Text);
end;

procedure TMethodReferenceCalledRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TMethodRefScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mScan := TMethodRefScan.Create(AContext.Text, AContext.Tree.Root, AContext.Index, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

procedure RegisterCompilerTrapMethodRefRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TMethodReferenceCalledRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.CompilerTraps.MethodRefs', cTexts);

end.
