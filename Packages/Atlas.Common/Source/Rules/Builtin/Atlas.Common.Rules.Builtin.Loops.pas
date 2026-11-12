unit Atlas.Common.Rules.Builtin.Loops;

// Regeln für Zählschleifen (#909, Gruppe Compiler vorab):
//   for-variable-misuse
//                     Die Variable einer for-Schleife wird im Rumpf zugewiesen
//                     oder mit Inc/Dec verändert (#1009, wie E2081), als
//                     var- bzw. out-Parameter an eine Routine dieser Datei
//                     übergeben (wie W1015) oder ist keine einfache lokale
//                     Variable: Feld der eigenen Klasse oder lokale Variable der
//                     umgebenden Routine (wie E1019), globale Variable der
//                     Unit (wie W1019). Parameter, unbekannte Namen und Schleifen in
//                     with-Anweisungen bleiben still, ebenso anonyme Methoden
//                     im Rumpf und Routinen mit Parserfehlern.
//                     Korrekturen: auf eine while-Schleife umstellen (nicht
//                     bei Continue im Rumpf) bzw. "for var" verwenden, wenn die
//                     Routine den Namen sonst nicht benutzt.
//   for-variable-after-loop
//                     Nach einer for-Schleife ist die Variable undefiniert,
//                     wenn die Schleife ohne Break endet (#1010, wie W1037).
//                     Vom normalen Ausgang der Schleife (Bedingungsknoten im
//                     Kontrollflussgraphen, Semantics.ControlFlow) folgt die
//                     Regel den Wegen bis zu einer Zuweisung; liest ein Knoten
//                     die Variable vorher sicher, meldet sie die Stelle. Eine
//                     unsichere Änderung (var-Argument, with, anonyme Methode)
//                     beendet den Weg ohne Meldung; Wege nur über mögliche
//                     Ausnahmen zählen nicht. Nur lokale Variablen der Routine,
//                     nicht for var. Korrektur wie oben: auf while umstellen,
//                     dann hat die Variable nach der Schleife einen Wert.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cForVariableMisuseRuleId = 'for-variable-misuse';
  cForVariableAfterLoopRuleId = 'for-variable-after-loop';

type
  TForVariableMisuseRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TForVariableAfterLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterLoopRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TLoopsText = (ToWhile, LoopVarTitle, Modified, VarParam, Assigned, OuterVariable, FieldKind, GlobalVariable,
    NonLocal, ReadAfterTitle, ReadAfter, UseForVar);

const
  cTexts: array[TLoopsText] of TAtlasText = (
    (De: 'Auf while-Schleife umstellen'; En: 'Convert to while loop'),
    (De: 'Schleifenvariable verändert oder nicht lokal'; En: 'Loop variable modified or not local'),
    (De: 'Schleifenvariable %s darf im Rumpf nicht verändert werden (wie E2081).';
     En: 'Loop variable %s must not be modified in the body (like E2081).'),
    (De: 'Schleifenvariable %s wird als var-Parameter an %s übergeben (wie W1015).';
     En: 'Loop variable %s is passed as var parameter to %s (like W1015).'),
    (De: 'Schleifenvariable %s darf im Rumpf nicht zugewiesen werden (wie E2081).';
     En: 'Loop variable %s must not be assigned in the body (like E2081).'),
    (De: 'eine Variable der umgebenden Routine'; En: 'a variable of the enclosing routine'),
    (De: 'ein Feld'; En: 'a field'),
    (De: 'eine globale Variable'; En: 'a global variable'),
    (De: 'Schleifenvariable %s ist %s, keine einfache lokale Variable (wie %s).';
     En: 'Loop variable %s is %s, not a simple local variable (like %s).'),
    (De: 'Schleifenvariable nach der Schleife gelesen'; En: 'Loop variable read after the loop'),
    (De: '%s ist nach der Schleife undefiniert, wenn kein Break erreicht wurde (wie W1037).';
     En: '%s is undefined after the loop if no Break was reached (like W1037).'),
    (De: 'for var %s verwenden'; En: 'Use for var %s'));

{$SCOPEDENUMS OFF}

type
  TNameSet = TDictionary<string, Boolean>;

/// <summary>Hat der Parser im Bereich von AScope einen Fehler gemeldet?</summary>
function ParserBroken(ATree: TSyntaxTree; AScope: TSyntaxNode): Boolean;
var
  mDiagnostic: TSyntaxDiagnostic;
begin
  for mDiagnostic in ATree.Diagnostics do
  begin
    if (mDiagnostic.StartPos.Line >= AScope.StartPos.Line) and (mDiagnostic.StartPos.Line <= AScope.EndPos.Line) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Fügt die Namen "A,B" in ASet ein (klein).</summary>
procedure AddNames(ASet: TNameSet; const ANames: string);
var
  mPart: string;
begin
  for mPart in ANames.Split([',']) do
  begin
    if Trim(mPart) <> '' then
    begin
      ASet.AddOrSetValue(LowerCase(Trim(mPart)), True);
    end;
  end;
end;

/// <summary>Variablen der Abschnitte var direkt unter AOwner (Routine oder Unit-Abschnitt).</summary>
procedure AddVariables(ASet: TNameSet; AOwner: TSyntaxNode);
var
  mIndex, mItem: Integer;
  mSection: TSyntaxNode;
begin
  for mIndex := 0 to AOwner.ChildCount - 1 do
  begin
    mSection := AOwner[mIndex];
    if mSection.Kind = TSyntaxKind.VarSection then
    begin
      for mItem := 0 to mSection.ChildCount - 1 do
      begin
        if mSection[mItem].Kind = TSyntaxKind.VarDecl then
        begin
          AddNames(ASet, mSection[mItem].Name);
        end;
      end;
    end;
  end;
end;

/// <summary>Bezeichner ohne Kette (I, nicht Self.I oder X.I).</summary>
function IsPlainName(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName);
end;

function SourceOf(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

// Leerraum am Anfang der Zeile, in der die Stelle AOffset (Spalte ACharacter) liegt.
function IndentAt(const AText: string; AOffset, ACharacter: Integer): string;
var
  mLineStart, mIndex: Integer;
begin
  mLineStart := AOffset - ACharacter;
  mIndex := mLineStart + 1;
  while (mIndex <= AOffset) and CharInSet(AText[mIndex], [' ', #9]) do
  begin
    Inc(mIndex);
  end;
  Result := Copy(AText, mLineStart + 1, mIndex - mLineStart - 1);
end;

// Kommt im Rumpf ein Continue dieser Schleife vor (nicht in einer inneren Schleife)?
function HasOwnContinue(ANode: TSyntaxNode): Boolean;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
        TSyntaxKind.RepeatStatement, TSyntaxKind.AnonymousMethod] then
      begin
        Continue;
      end;
      if (mNode.Kind = TSyntaxKind.CallStatement) and SameText(mNode.Name, 'Continue') then
      begin
        Exit(True);
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

type
  /// <summary>Teile der Umstellung einer for- auf eine while-Schleife.</summary>
  TWhileParts = record
    /// <summary>Ersatz für "for … do": Startzuweisung und "while … do".</summary>
    Head: string;
    /// <summary>Inc bzw. Dec.</summary>
    Step: string;
    LineBreak: string;
    Indent: string;
    /// <summary>Das do der for-Schleife.</summary>
    DoToken: Integer;
  end;

/// <summary>Vergleich und Schritt der Schleife: downto zwischen AStart und AStop zählt rückwärts.</summary>
procedure LoopDirection(const ATokens: TArray<TPascalToken>; AStart, AStop: TSyntaxNode; out ACompare,
  AStep: string);
var
  mIndex: Integer;
begin
  ACompare := '<=';
  AStep := 'Inc';
  for mIndex := TokenFrom(ATokens, AStart.EndOffset) to TokenFrom(ATokens, AStop.StartOffset) do
  begin
    if (mIndex <= High(ATokens)) and ATokens[mIndex].IsKeyword('downto') then
    begin
      ACompare := '>=';
      AStep := 'Dec';
    end;
  end;
end;

/// <summary>Startzuweisung "I := A;", mit AInline als "var I: Typ := A;".</summary>
function LoopStart(const AText: string; ALoop, AStartExpr: TSyntaxNode; AInline: Boolean): string;
var
  mTypeRef: TSyntaxNode;
begin
  mTypeRef := ALoop.FindChild(TSyntaxKind.TypeReference);
  Result := ALoop.Name + ' := ' + SourceOf(AText, AStartExpr) + ';';
  if AInline and (mTypeRef <> nil) then
  begin
    Result := 'var ' + ALoop.Name + ': ' + SourceOf(AText, mTypeRef) + ' := ' + SourceOf(AText, AStartExpr) + ';';
  end
  else if AInline then
  begin
    Result := 'var ' + Result;
  end;
end;

/// <summary>Änderungen für einen Rumpf mit begin … end: vor dem end Inc(I); fehlt das Semikolon nach der letzten
/// Anweisung, kommt es dazu. False ohne end.</summary>
function BlockLoopEdits(const AText: string; const ATokens: TArray<TPascalToken>; ALoop, ABody: TSyntaxNode;
  const AParts: TWhileParts; out AEdits: TArray<TRuleEdit>): Boolean;
var
  mEnd, mBefore: Integer;
begin
  AEdits := nil;
  mEnd := PreviousCode(ATokens, TokenFrom(ATokens, ABody.EndOffset));
  Result := (mEnd >= 0) and ATokens[mEnd].IsKeyword('end');
  if not Result then
  begin
    Exit;
  end;
  AEdits := [TRuleEdit.Create(TTextRange.Create(ALoop.StartPos, ATokens[AParts.DoToken].EndPos), AParts.Head)];
  mBefore := PreviousCode(ATokens, mEnd);
  if (mBefore >= 0) and not ATokens[mBefore].IsSymbol(';') and not ATokens[mBefore].IsKeyword('begin') then
  begin
    AEdits := AEdits + [TRuleEdit.Create(TTextRange.Create(ATokens[mBefore].EndPos, ATokens[mBefore].EndPos), ';')];
  end;
  AEdits := AEdits + [TRuleEdit.Create(TTextRange.Create(ATokens[mEnd].StartPos, ATokens[mEnd].StartPos),
    '  ' + AParts.Step + '(' + ALoop.Name + ');' + AParts.LineBreak + IndentAt(AText, ATokens[mEnd].Offset,
    ATokens[mEnd].StartPos.Character))];
end;

/// <summary>Änderungen für einen Rumpf aus einer Anweisung: in begin … end mit Inc(I) einschließen.</summary>
function SingleLoopEdits(const ATokens: TArray<TPascalToken>; ALoop, ABody: TSyntaxNode;
  const AParts: TWhileParts): TArray<TRuleEdit>;
begin
  Result := [TRuleEdit.Create(TTextRange.Create(ALoop.StartPos, ATokens[AParts.DoToken].EndPos),
    AParts.Head + AParts.LineBreak + AParts.Indent + 'begin'),
    TRuleEdit.Create(TTextRange.Create(ABody.EndPos, ABody.EndPos), ';' + AParts.LineBreak + AParts.Indent + '  ' +
    AParts.Step + '(' + ALoop.Name + ');' + AParts.LineBreak + AParts.Indent + 'end')];
end;

// Korrektur: for I := A to B do S wird I := A; while I <= B do begin S; Inc(I); end.
function WhileLoopFix(const AText: string; const ATokens: TArray<TPascalToken>; ALoop: TSyntaxNode;
  AInline: Boolean): TArray<TRuleFix>;
var
  mStartExpr, mStopExpr, mBody: TSyntaxNode;
  mCompare: string;
  mParts: TWhileParts;
  mEdits: TArray<TRuleEdit>;
begin
  Result := nil;
  if (ALoop.ChildCount < 3) or HasOwnContinue(ALoop[ALoop.ChildCount - 1]) then
  begin
    Exit;
  end;
  mStartExpr := ALoop[ALoop.ChildCount - 3];
  mStopExpr := ALoop[ALoop.ChildCount - 2];
  mBody := ALoop[ALoop.ChildCount - 1];
  mParts := Default(TWhileParts);
  mParts.LineBreak := #10;
  if Pos(#13#10, AText) > 0 then
  begin
    mParts.LineBreak := #13#10;
  end;
  LoopDirection(ATokens, mStartExpr, mStopExpr, mCompare, mParts.Step);
  mParts.DoToken := PreviousCode(ATokens, TokenFrom(ATokens, mBody.StartOffset));
  if (mParts.DoToken < 0) or not ATokens[mParts.DoToken].IsKeyword('do') then
  begin
    Exit;
  end;
  mParts.Indent := IndentAt(AText, ALoop.StartOffset, ALoop.StartPos.Character);
  mParts.Head := LoopStart(AText, ALoop, mStartExpr, AInline) + mParts.LineBreak + mParts.Indent + 'while ' +
    ALoop.Name + ' ' + mCompare + ' ' + SourceOf(AText, mStopExpr) + ' do';
  if mBody.Kind <> TSyntaxKind.Block then
  begin
    mEdits := SingleLoopEdits(ATokens, ALoop, mBody, mParts);
  end
  else if not BlockLoopEdits(AText, ATokens, ALoop, mBody, mParts, mEdits) then
  begin
    Exit;
  end;
  Result := [TRuleFix.Create(cTexts[TLoopsText.ToWhile].Text, mEdits)];
end;

{ TForVariableMisuseRule }

function TForVariableMisuseRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cForVariableMisuseRuleId, TRuleSeverity.Error,
    cTexts[TLoopsText.LoopVarTitle].Text);
end;

procedure TForVariableMisuseRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mGlobals, mFields: TNameSet;
  mVarRoutines: TDictionary<string, TArray<TArray<Boolean>>>;


  // var- bzw. out-Modus jedes Parameters des Kopfs AHeader in Reihenfolge.
  function ParameterModes(AHeader: TSyntaxNode): TArray<Boolean>;
  var
    mParams: TSyntaxNode;
    mItem, mCount: Integer;
  begin
    Result := nil;
    mParams := AHeader.FindChild(TSyntaxKind.Parameters);
    if mParams = nil then
    begin
      Exit;
    end;
    for mItem := 0 to mParams.ChildCount - 1 do
    begin
      if mParams[mItem].Kind <> TSyntaxKind.Parameter then
      begin
        Continue;
      end;
      for mCount := 1 to Length(mParams[mItem].Name.Split([','])) do
      begin
        Result := Result + [mParams[mItem].Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam]];
      end;
    end;
  end;

  // Merkt sich die Parametermodi der Routine mit dem Kopf AHeader unter ihrem Namen ohne Klasse.
  procedure AddVarRoutine(AHeader: TSyntaxNode);
  var
    mKey: string;
    mKnown: TArray<TArray<Boolean>>;
  begin
    mKey := LowerCase(AHeader.Name);
    if Pos('.', mKey) > 0 then
    begin
      mKey := Copy(mKey, LastDelimiter('.', mKey) + 1, MaxInt);
    end;
    if not mVarRoutines.TryGetValue(mKey, mKnown) then
    begin
      mKnown := nil;
    end;
    mVarRoutines.AddOrSetValue(mKey, mKnown + [ParameterModes(AHeader)]);
  end;

  procedure AddFields(AField: TSyntaxNode; const AClassName: string);
  var
    mKey: string;
  begin
    for mKey in AField.Name.Split([',']) do
    begin
      mFields.AddOrSetValue(AClassName + '.' + LowerCase(Trim(mKey)), True);
    end;
  end;

  // Felder der Klassen dieser Datei (Typname klein -> Feldnamen) und Routinen mit var/out-Parametern.
  procedure CollectDeclarations(ANode: TSyntaxNode; const AClass: string);
  var
    mIndex: Integer;
    mChild: TSyntaxNode;
    mClassName: string;
    mPending: TStack<TSyntaxNode>;
    mClasses: TStack<string>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht): zu jedem Kind auf dem Stapel der Name der umgebenden Klasse.
    mPending := TStack<TSyntaxNode>.Create;
    mClasses := TStack<string>.Create;
    try
      for mIndex := ANode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(ANode[mIndex]);
        mClasses.Push(AClass);
      end;
      while mPending.Count > 0 do
      begin
        mChild := mPending.Pop;
        mClassName := mClasses.Pop;
        if (mChild.Kind = TSyntaxKind.Field) and (mClassName <> '') then
        begin
          AddFields(mChild, mClassName);
        end
        else if mChild.Kind = TSyntaxKind.TypeDecl then
        begin
          mClassName := LowerCase(mChild.Name);
        end
        else if mChild.Kind = TSyntaxKind.RoutineHeader then
        begin
          AddVarRoutine(mChild);
        end;
        for mIndex := mChild.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mChild[mIndex]);
          mClasses.Push(mClassName);
        end;
      end;
    finally
      mClasses.Free;
      mPending.Free;
    end;
  end;

  // Übergibt jede Deklaration von AName an der Stelle AArgument einen var- bzw. out-Parameter?
  function PassesByReference(const AName: string; AArgument: Integer): Boolean;
  var
    mKnown: TArray<TArray<Boolean>>;
    mModes: TArray<Boolean>;
  begin
    Result := False;
    if not mVarRoutines.TryGetValue(LowerCase(AName), mKnown) then
    begin
      Exit;
    end;
    for mModes in mKnown do
    begin
      if (AArgument > High(mModes)) or not mModes[AArgument] then
      begin
        Exit(False);
      end;
    end;
    Result := True;
  end;


  // Inc/Dec und var-Übergabe der Schleifenvariablen AName als Argument des Aufrufs ACall.
  procedure CheckCallArguments(ACall, ALoop: TSyntaxNode; const AName: string; AInline: Boolean);
  var
    mIndex: Integer;
    mTarget: TSyntaxNode;
    mName: string;
  begin
    mName := ACall[0].Name;
    for mIndex := 1 to ACall.ChildCount - 1 do
    begin
      mTarget := ACall[mIndex];
      if not IsPlainName(mTarget, AName) then
      begin
        Continue;
      end;
      if (mIndex = 1) and MatchText(mName, ['Inc', 'Dec']) and not mVarRoutines.ContainsKey('inc') and
        not mVarRoutines.ContainsKey('dec') then
      begin
        AReport.Add(TTextRange.Create(mTarget.StartPos, mTarget.EndPos),
          cTexts[TLoopsText.Modified].Fmt([AName]),
          TRuleConfidence.High, WhileLoopFix(AContext.Text, mTokens, ALoop, AInline));
      end
      else if PassesByReference(mName, mIndex - 1) then
      begin
        AReport.Add(TTextRange.Create(mTarget.StartPos, mTarget.EndPos),
          cTexts[TLoopsText.VarParam].Fmt([AName, mName]),
          TRuleConfidence.High);
      end;
    end;
  end;

  // Anweisung "Name(Argumente);" mit einfachem Namen?
  function IsNamedCall(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount = 1) and
      (ANode[0].Kind = TSyntaxKind.Call) and (ANode[0].ChildCount > 1);
    Result := Result and (ANode[0][0].Kind = TSyntaxKind.Identifier);
  end;

  // Anonyme Methoden laufen später, with kann den Namen umdeuten, eine innere Schleife mit demselben Namen prüft
  // der eigene Durchlauf.
  function SkipsBody(ANode: TSyntaxNode; const AName: string): Boolean;
  begin
    Result := (ANode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.WithStatement]) or
      ((ANode.Kind = TSyntaxKind.ForStatement) and SameText(ANode.Name, AName));
  end;

  // Meldungen im Rumpf: Zuweisung, Inc/Dec und var-Übergabe der Schleifenvariablen AName.
  procedure CheckBody(ABody, ALoop: TSyntaxNode; const AName: string; AInline: Boolean);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ABody);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if SkipsBody(mNode, AName) then
        begin
          Continue;
        end;
        if (mNode.Kind = TSyntaxKind.AssignStatement) and (mNode.ChildCount > 0) and IsPlainName(mNode[0], AName) then
        begin
          AReport.Add(TTextRange.Create(mNode[0].StartPos, mNode[0].EndPos),
            cTexts[TLoopsText.Assigned].Fmt([AName]),
            TRuleConfidence.High, WhileLoopFix(AContext.Text, mTokens, ALoop, AInline));
        end
        else if IsNamedCall(mNode) then
        begin
          CheckCallArguments(mNode[0], ALoop, AName, AInline);
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

  // Kommt AName in ANode außerhalb von ALoop vor?
  function UsedOutside(ANode, ALoop: TSyntaxNode; const AName: string): Boolean;
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    Result := False;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode = ALoop then
        begin
          Continue;
        end;
        if (mNode.Kind = TSyntaxKind.Identifier) and SameText(mNode.Name, AName) then
        begin
          Exit(True);
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

  // Schleifen der Routine ARoutine (Rumpf ABody); AOuterLocals: Variablen der umgebenden Routinen.
  procedure CheckRoutine(ARoutine, ABody: TSyntaxNode; AOuterLocals: TNameSet; const AClass: string);
  var
    mLocals: TNameSet;
    mHeader, mParams: TSyntaxNode;
    mIndex: Integer;

    procedure CollectInline(ARoot: TSyntaxNode);
    var
      mChild: Integer;
      mNode: TSyntaxNode;
      mPending: TStack<TSyntaxNode>;
    begin
      // Iterativ (tiefe Bäume sprengen den Stapel nicht).
      mPending := TStack<TSyntaxNode>.Create;
      try
        mPending.Push(ARoot);
        while mPending.Count > 0 do
        begin
          mNode := mPending.Pop;
          if mNode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
          begin
            Continue;
          end;
          if mNode.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
          begin
            AddNames(mLocals, mNode.Name);
          end;
          for mChild := mNode.ChildCount - 1 downto 0 do
          begin
            mPending.Push(mNode[mChild]);
          end;
        end;
      finally
        mPending.Free;
      end;
    end;

    // Art der nicht lokalen Schleifenvariablen AKey ('' bei unbekannter) und der Code der Meldung. Eine globale
    // Variable übersetzt Delphi 13 mit Warnung W1019, die anderen Fälle sind Fehler E1019.
    function NonLocalKind(const AKey: string; out ACode: string): string;
    begin
      Result := '';
      ACode := 'E1019';
      if AOuterLocals.ContainsKey(AKey) then
      begin
        Result := cTexts[TLoopsText.OuterVariable].Text;
      end
      else if (AClass <> '') and mFields.ContainsKey(AClass + '.' + AKey) then
      begin
        Result := cTexts[TLoopsText.FieldKind].Text;
      end
      else if mGlobals.ContainsKey(AKey) then
      begin
        Result := cTexts[TLoopsText.GlobalVariable].Text;
        ACode := 'W1019';
      end;
    end;

    // Nicht lokal: lokale Variable einer umgebenden Routine, Feld der eigenen Klasse oder globale Variable.
    procedure CheckNonLocal(ALoop: TSyntaxNode; AForToken: Integer);
    var
      mKind, mCode: string;
      mFixes: TArray<TRuleFix>;
    begin
      mKind := NonLocalKind(LowerCase(ALoop.Name), mCode);
      if mKind = '' then
      begin
        Exit;
      end;
      mFixes := nil;
      if not UsedOutside(ABody, ALoop, ALoop.Name) then
      begin
        mFixes := [TRuleFix.Create(cTexts[TLoopsText.UseForVar].Fmt([ALoop.Name]),
          [TRuleEdit.Create(TTextRange.Create(mTokens[AForToken].StartPos, mTokens[AForToken].StartPos), 'var ')])];
      end;
      AReport.Add(TTextRange.Create(mTokens[AForToken].StartPos, mTokens[AForToken].EndPos),
        cTexts[TLoopsText.NonLocal].Fmt([ALoop.Name, mKind, mCode]),
        TRuleConfidence.High, mFixes);
    end;

    procedure CheckFor(ALoop: TSyntaxNode);
    var
      mForToken: Integer;
      mIsInline: Boolean;
    begin
      // Erstes Code-Token nach for: var bei for var I, sonst der Name.
      mForToken := NextCode(mTokens, TokenFrom(mTokens, ALoop.StartOffset) + 1);
      mIsInline := (mForToken <= High(mTokens)) and mTokens[mForToken].IsKeyword('var');
      if not mIsInline and not mLocals.ContainsKey(LowerCase(ALoop.Name)) then
      begin
        CheckNonLocal(ALoop, mForToken);
      end;
      if ALoop.ChildCount > 0 then
      begin
        CheckBody(ALoop[ALoop.ChildCount - 1], ALoop, ALoop.Name, mIsInline);
      end;
    end;

    procedure VisitLoops(ARoot: TSyntaxNode);
    var
      mChild: Integer;
      mInWith: Boolean;
      mNode: TSyntaxNode;
      mPending: TStack<TSyntaxNode>;
      mPendingInWith: TStack<Boolean>;
    begin
      // Iterativ (tiefe Bäume sprengen den Stapel nicht): zu jedem Knoten auf dem Stapel, ob er in einer with-Anweisung
      // liegt.
      mPending := TStack<TSyntaxNode>.Create;
      mPendingInWith := TStack<Boolean>.Create;
      try
        mPending.Push(ARoot);
        mPendingInWith.Push(False);
        while mPending.Count > 0 do
        begin
          mNode := mPending.Pop;
          mInWith := mPendingInWith.Pop or (mNode.Kind = TSyntaxKind.WithStatement);
          if mNode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
          begin
            Continue;
          end;
          if (mNode.Kind = TSyntaxKind.ForStatement) and (mNode.Name <> '') and not mInWith then
          begin
            CheckFor(mNode);
          end;
          for mChild := mNode.ChildCount - 1 downto 0 do
          begin
            mPending.Push(mNode[mChild]);
            mPendingInWith.Push(mInWith);
          end;
        end;
      finally
        mPendingInWith.Free;
        mPending.Free;
      end;
    end;

  var
    mOuter: TNameSet;
    mChild: TSyntaxNode;
    mPair: TPair<string, Boolean>;
  begin
    mLocals := TNameSet.Create;
    mOuter := TNameSet.Create;
    try
      AddVariables(mLocals, ARoutine);
      mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
      if mHeader <> nil then
      begin
        mParams := mHeader.FindChild(TSyntaxKind.Parameters);
        if mParams <> nil then
        begin
          for mIndex := 0 to mParams.ChildCount - 1 do
          begin
            AddNames(mLocals, mParams[mIndex].Name);
          end;
        end;
      end;
      CollectInline(ABody);
      if not ParserBroken(AContext.Tree, ARoutine) then
      begin
        VisitLoops(ABody);
      end;
      // Lokale Routinen: deren umgebende Variablen sind diese plus die äußeren. Die Rekursion bleibt:
      // sie geht nur über verschachtelte Routinendeklarationen, nicht über Ausdrücke oder Anweisungsketten.
      for mPair in AOuterLocals do
      begin
        mOuter.AddOrSetValue(mPair.Key, True);
      end;
      for mPair in mLocals do
      begin
        mOuter.AddOrSetValue(mPair.Key, True);
      end;
      for mIndex := 0 to ARoutine.ChildCount - 1 do
      begin
        mChild := ARoutine[mIndex];
        if (mChild.Kind = TSyntaxKind.RoutineDecl) and (mChild.FindChild(TSyntaxKind.Block) <> nil) then
        begin
          CheckRoutine(mChild, mChild.FindChild(TSyntaxKind.Block), mOuter, AClass);
        end;
      end;
    finally
      mOuter.Free;
      mLocals.Free;
    end;
  end;

  procedure VisitRoutines(ANode: TSyntaxNode);
  var
    mIndex: Integer;
    mBody: TSyntaxNode;
    mClassName: string;
    mNoOuter: TNameSet;
  begin
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      mBody := ANode[mIndex];
      if (mBody.Kind = TSyntaxKind.RoutineDecl) and (mBody.FindChild(TSyntaxKind.Block) <> nil) then
      begin
        mClassName := '';
        if Pos('.', mBody.Name) > 0 then
        begin
          mClassName := LowerCase(Copy(mBody.Name, 1, LastDelimiter('.', mBody.Name) - 1));
        end;
        mNoOuter := TNameSet.Create;
        try
          CheckRoutine(mBody, mBody.FindChild(TSyntaxKind.Block), mNoOuter, mClassName);
        finally
          mNoOuter.Free;
        end;
      end
      else if mBody.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
      begin
        VisitRoutines(mBody);
      end;
    end;
  end;

  procedure CollectGlobals(ANode: TSyntaxNode);
  var
    mIndex: Integer;
  begin
    AddVariables(mGlobals, ANode);
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      if ANode[mIndex].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
      begin
        AddVariables(mGlobals, ANode[mIndex]);
      end;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'for') then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mGlobals := TNameSet.Create;
  mFields := TNameSet.Create;
  mVarRoutines := TDictionary<string, TArray<TArray<Boolean>>>.Create;
  try
    CollectGlobals(AContext.Tree.Root);
    CollectDeclarations(AContext.Tree.Root, '');
    VisitRoutines(AContext.Tree.Root);
  finally
    mVarRoutines.Free;
    mFields.Free;
    mGlobals.Free;
  end;
end;

{ TForVariableAfterLoopRule }

function TForVariableAfterLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cForVariableAfterLoopRuleId, TRuleSeverity.Warning,
    cTexts[TLoopsText.ReadAfterTitle].Text);
end;

procedure TForVariableAfterLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCache: IRuleDerivedCache;
  mGraph: TControlFlowGraph;
  mTokens: TArray<TPascalToken>;
  mReported: TDictionary<TSyntaxNode, Boolean>;

  function IsInside(ANode, AOuter: TSyntaxNode): Boolean;
  begin
    while (ANode <> nil) and (ANode <> AOuter) do
    begin
      ANode := ANode.Parent;
    end;
    Result := ANode <> nil;
  end;

  // Erster Bezeichner AName im Ausdrucksteil von ASyntax (nicht in eingebetteten Anweisungen oder anonymen
  // Methoden); nil ohne.
  function FindName(ASyntax: TSyntaxNode; const AName: string): TSyntaxNode;
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    Result := nil;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ASyntax);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.AnonymousMethod then
        begin
          Continue;
        end;
        if (mNode.Kind = TSyntaxKind.Identifier) and SameText(mNode.Name, AName) then
        begin
          Exit(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          if not (mNode[mIndex].Kind in [TSyntaxKind.Block, TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
            TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.CaseItem, TSyntaxKind.CaseElse,
            TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
            TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement,
            TSyntaxKind.RaiseStatement, TSyntaxKind.LabeledStatement]) then
          begin
            mPending.Push(mNode[mIndex]);
          end;
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  // Führt ANext in den Rumpf von ALoop? Knoten ohne Syntax (Sprungziel am Anfang von repeat) bis zur ersten
  // Anweisung verfolgen.
  function EntersBody(ANext: TFlowNode; ALoop: TSyntaxNode): Boolean;
  var
    mNode, mNext: TFlowNode;
    mPending: TStack<TFlowNode>;
    mSeen: TDictionary<TFlowNode, Boolean>;
  begin
    Result := False;
    mPending := TStack<TFlowNode>.Create;
    mSeen := TDictionary<TFlowNode, Boolean>.Create;
    try
      mPending.Push(ANext);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mSeen.ContainsKey(mNode) then
        begin
          Continue;
        end;
        mSeen.Add(mNode, True);
        if mNode.Syntax <> nil then
        begin
          if IsInside(mNode.Syntax, ALoop) and (mNode.Syntax <> ALoop) then
          begin
            Exit(True);
          end;
          Continue;
        end;
        for mNext in mNode.Successors do
        begin
          mPending.Push(mNext);
        end;
      end;
    finally
      mSeen.Free;
      mPending.Free;
    end;
  end;

  // Erreichbarer Bedingungsknoten der Schleife ALoop; nil ohne.
  function ConditionOf(ALoop: TSyntaxNode): TFlowNode;
  var
    mNode: TFlowNode;
  begin
    Result := nil;
    for mNode in mGraph.Nodes do
    begin
      if (mNode.Kind = TFlowNodeKind.Condition) and (mNode.Syntax = ALoop) then
      begin
        Result := mNode;
      end;
    end;
    if (Result <> nil) and (mGraph.IsReachable(Result) <> TFlowAnswer.Yes) then
    begin
      Result := nil;
    end;
  end;

  // Normaler Ausgang: Nachfolger ANext der Bedingung ACondition außerhalb der Schleife.
  function IsLoopExit(ANext, ACondition: TFlowNode; ALoop: TSyntaxNode): Boolean;
  begin
    Result := (ANext <> ACondition) and (((ANext.Syntax = nil) and not EntersBody(ANext, ALoop)) or
      ((ANext.Syntax <> nil) and not IsInside(ANext.Syntax, ALoop)));
  end;

  procedure ReportRead(ANode: TFlowNode; ALoop: TSyntaxNode);
  var
    mTarget: TSyntaxNode;
  begin
    mTarget := FindName(ANode.Syntax, ALoop.Name);
    if (mTarget = nil) or mReported.ContainsKey(mTarget) then
    begin
      Exit;
    end;
    mReported.Add(mTarget, True);
    AReport.Add(TTextRange.Create(mTarget.StartPos, mTarget.EndPos), cTexts[TLoopsText.ReadAfter].Fmt([ALoop.Name]),
      TRuleConfidence.High,
      WhileLoopFix(AContext.Text, mTokens, ALoop, False));
  end;

  // Folgt dem Fluss ab ANode, solange die Schleifenvariable weder neu belegt noch gelesen wird; ein Lesen meldet
  // ReportRead.
  procedure FollowFlow(ANode: TFlowNode; ALoop: TSyntaxNode; APending: TStack<TFlowNode>);
  var
    mNext: TFlowNode;
  begin
    if SameText(ANode.Defines, ALoop.Name) or ANode.TouchesName(ALoop.Name) then
    begin
      Exit;
    end;
    if ANode.ReadsName(ALoop.Name) and (ANode.Syntax <> nil) then
    begin
      ReportRead(ANode, ALoop);
      Exit;
    end;
    for mNext in ANode.Successors do
    begin
      if not ANode.IsImplicitRaiseEdge(mNext) then
      begin
        APending.Push(mNext);
      end;
    end;
  end;

  procedure CheckLoop(ALoop: TSyntaxNode);
  var
    mCondition, mNode, mNext: TFlowNode;
    mPending: TStack<TFlowNode>;
    mSeen: TDictionary<TFlowNode, Boolean>;
  begin
    mCondition := ConditionOf(ALoop);
    if mCondition = nil then
    begin
      Exit;
    end;
    mPending := TStack<TFlowNode>.Create;
    mSeen := TDictionary<TFlowNode, Boolean>.Create;
    try
      for mNext in mCondition.Successors do
      begin
        if IsLoopExit(mNext, mCondition, ALoop) then
        begin
          mPending.Push(mNext);
        end;
      end;
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mSeen.ContainsKey(mNode) then
        begin
          Continue;
        end;
        mSeen.Add(mNode, True);
        FollowFlow(mNode, ALoop, mPending);
      end;
    finally
      mSeen.Free;
      mPending.Free;
    end;
  end;

  procedure VisitLoops(ARoot: TSyntaxNode; ALocals: TNameSet);
  var
    mIndex, mForToken: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
        begin
          Continue;
        end;
        if (mNode.Kind = TSyntaxKind.ForStatement) and ALocals.ContainsKey(LowerCase(mNode.Name)) then
        begin
          mForToken := NextCode(mTokens, TokenFrom(mTokens, mNode.StartOffset) + 1);
          if (mForToken <= High(mTokens)) and not mTokens[mForToken].IsKeyword('var') then
          begin
            CheckLoop(mNode);
          end;
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

var
  mRoutine, mBlock: TSyntaxNode;
  mLocals: TNameSet;
begin
  if (AContext.Tree = nil) or not ContainsText(AContext.Text, 'for') then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mCache := TRuleDerived.Open(AContext);
  mReported := TDictionary<TSyntaxNode, Boolean>.Create;
  mLocals := TNameSet.Create;
  try
    for mRoutine in TRuleDerived.Routines(mCache, AContext) do
    begin
      mBlock := mRoutine.FindChild(TSyntaxKind.Block);
      if mBlock = nil then
      begin
        Continue;
      end;
      mLocals.Clear;
      AddVariables(mLocals, mRoutine);
      if mLocals.Count = 0 then
      begin
        Continue;
      end;
      mGraph := TRuleDerived.Graph(mCache, AContext, mRoutine);
      if (mGraph = nil) or not mGraph.Complete then
      begin
        Continue;
      end;
      VisitLoops(mBlock, mLocals);
    end;
  finally
    mLocals.Free;
    mReported.Free;
  end;
end;

procedure RegisterLoopRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TForVariableMisuseRule.Create);
  ARegistry.Register(TForVariableAfterLoopRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Loops', cTexts);

end.
