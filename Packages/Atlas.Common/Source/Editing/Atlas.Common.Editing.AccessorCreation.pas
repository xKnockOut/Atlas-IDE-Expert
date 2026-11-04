unit Atlas.Common.Editing.AccessorCreation;

// Feld und Zugriffsmethoden einer Eigenschaft anlegen (#467, ARG-068): Die
// Vervollständigung nach "read " bzw. "write " einer Eigenschaftsdeklaration
// bietet „Feld F<Name> anlegen“, „Get<Name> anlegen“ und „Set<Name> anlegen“.
//   - Das Feld kommt in den private-Abschnitt, bei strict private in der Klasse
//     dorthin, hinter die Felder am Anfang des Abschnitts.
//   - Methoden kommen ans Ende des Abschnitts nach completion.accessorSection,
//     liegt die Eigenschaft selbst darin, direkt vor sie.
//   - Delphi verlangt Feld und Methoden vor der Eigenschaft: Steht der
//     Abschnitt erst dahinter oder fehlt er, entsteht vor der Eigenschaft ein
//     eigener Abschnitt, danach geht ihr Abschnitt weiter.
//   - Der Getter liefert das Feld F<Name>, wenn es das gibt, sonst
//     Default(Typ); der Setter prüft auf Änderung wie /prop (#51, #320), bei
//     nicht vergleichbaren Typen (Records, Arrays, Methodenzeiger) ohne
//     Prüfung. Fehlt das Feld, legt „Set<Name> anlegen“ es mit an.
//   - Indexeigenschaften: Indexparameter vor Value, kein Feld.
// Die Eigenschaftszeile ist die Befehlszeile von TCommandSource: Der Baum
// sieht sie nicht, sie ist ohnehin unvollständig.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.CommandSource;

type
  {$SCOPEDENUMS ON}
  TAccessorKind = (Field, Getter, Setter);
  {$SCOPEDENUMS OFF}

  TAccessorPlan = record
    Kind: TAccessorKind;
    /// <summary>Name der Eigenschaft (Caption).</summary>
    PropertyName: string;
    PropertyType: string;
    /// <summary>Indexparameter ohne Klammern ("Index: Integer"); '' ohne.</summary>
    IndexParameters: string;
    /// <summary>Abschnitt der Methoden: private oder protected.</summary>
    MethodSection: string;
    /// <summary>Name des neuen Mitglieds: FCaption, GetCaption, SetCaption.</summary>
    function Name: string;
    function FieldName: string;
  end;

  TAccessorCreation = class
  public
    /// <summary>Deklaration ohne Einrückung: "FCaption: string;", "function GetCaption: string;",
    /// "procedure SetCaption(const Value: string);".</summary>
    class function Declaration(const APlan: TAccessorPlan): string; static;
    /// <summary>Lässt sich der Typ mit &lt;&gt; vergleichen? Nein bei array, TArray&lt;&gt;, Records,
    /// prozeduralen Typen und Methodenzeigern (über AIndex, Aliase bis drei Stufen); unbekannte Typen ja.</summary>
    class function IsComparable(const ATypeName: string; const AIndex: ISymbolIndex): Boolean; overload; static;
    /// <summary>Wie oben, Typen der eigenen Unit AUnit zuerst (noch nicht im Index).</summary>
    class function IsComparable(const ATypeName: string; const AIndex: ISymbolIndex;
      const AUnit: TUnitIndex): Boolean; overload; static;
    /// <summary>Änderungen für APlan in der Klasse AClass mit der Eigenschaft in Zeile ASource.Line: Deklaration(en)
    /// und Rumpf; False, wenn das Mitglied schon da ist oder die Klasse nicht passt. AWithField: Der Setter legt
    /// auch das Feld an.</summary>
    class function Edits(ASource: TCommandSource; const AIndex: ISymbolIndex; const AClass: TIndexSymbol;
      const APlan: TAccessorPlan; out AEdits: TArray<TTextEdit>; out AWithField: Boolean): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Editing.ClassMembers;

{ TAccessorPlan }

function TAccessorPlan.FieldName: string;
begin
  Result := 'F' + PropertyName;
end;

function TAccessorPlan.Name: string;
begin
  case Kind of
    TAccessorKind.Getter:
      Result := 'Get' + PropertyName;
    TAccessorKind.Setter:
      Result := 'Set' + PropertyName;
  else
    Result := FieldName;
  end;
end;

{ TAccessorCreation }

class function TAccessorCreation.Declaration(const APlan: TAccessorPlan): string;
var
  Index: string;
begin
  case APlan.Kind of
    TAccessorKind.Getter:
      begin
        Result := 'function ' + APlan.Name;
        if APlan.IndexParameters <> '' then
        begin
          Result := Result + '(' + APlan.IndexParameters + ')';
        end;
        Result := Result + ': ' + APlan.PropertyType + ';';
      end;
    TAccessorKind.Setter:
      begin
        Index := '';
        if APlan.IndexParameters <> '' then
        begin
          Index := APlan.IndexParameters + '; ';
        end;
        Result := Format('procedure %s(%sconst Value: %s);', [APlan.Name, Index, APlan.PropertyType]);
      end;
  else
    Result := Format('%s: %s;', [APlan.FieldName, APlan.PropertyType]);
  end;
end;

class function TAccessorCreation.IsComparable(const ATypeName: string; const AIndex: ISymbolIndex): Boolean;
begin
  Result := IsComparable(ATypeName, AIndex, Default(TUnitIndex));
end;

function IsTypeSymbol(const ASymbol: TIndexSymbol; const AName: string): Boolean;
begin
  Result := (ASymbol.Container = '') and SameText(ASymbol.Name, AName) and (ASymbol.Kind in
    [TIndexSymbolKind.ClassType, TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType,
    TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias, TIndexSymbolKind.ObjectType]);
end;

/// <summary>Typ AName in AUnit, sonst im Index.</summary>
function FindType(const AName: string; const AIndex: ISymbolIndex; const AUnit: TUnitIndex;
  out ASymbol: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  for Symbol in AUnit.Symbols do
  begin
    if IsTypeSymbol(Symbol, AName) then
    begin
      ASymbol := Symbol;
      Exit(True);
    end;
  end;
  if AIndex <> nil then
  begin
    for Location in AIndex.FindSymbols(AName) do
    begin
      if IsTypeSymbol(Location.Symbol, AName) then
      begin
        ASymbol := Location.Symbol;
        Exit(True);
      end;
    end;
  end;
  ASymbol := Default(TIndexSymbol);
  Result := False;
end;

type
  {$SCOPEDENUMS ON}
  /// <summary>Ergebnis einer Stufe von IsComparable: vergleichbar, nicht vergleichbar oder Alias auf einen
  /// weiteren Typ.</summary>
  TComparability = (Comparable, Uncomparable, Alias);
  {$SCOPEDENUMS OFF}

const
  /// <summary>Typtexte mit diesen Anfängen lassen sich nicht mit &lt;&gt; vergleichen.</summary>
  cUncomparablePrefixes: array[0..5] of string = ('array', 'TArray<', 'procedure', 'function', 'reference',
    'record');

/// <summary>Zeigt schon der Typtext einen nicht vergleichbaren Typ (Array, prozeduraler Typ, Record)?</summary>
function IsUncomparableText(const AName: string): Boolean;
var
  mPrefix: string;
begin
  Result := SameText(AName, 'TBytes');
  for mPrefix in cUncomparablePrefixes do
  begin
    Result := Result or StartsText(mPrefix, AName);
  end;
end;

/// <summary>Rechte Seite einer Aliasdeklaration ohne "type ": "TNotifyEvent = procedure(Sender: TObject) of
/// object", "TPunkte = array of TPunkt", "TName = string".</summary>
function AliasTarget(const ASignature: string): string;
begin
  Result := ASignature;
  if Pos('=', Result) > 0 then
  begin
    Result := Trim(Copy(Result, Pos('=', Result) + 1, MaxInt));
  end;
  if StartsText('type ', Result) then
  begin
    Result := Trim(Copy(Result, 6, MaxInt));
  end;
end;

/// <summary>Eine Stufe von IsComparable für den Typtext AName; ATarget ist bei Alias der nächste Typtext.</summary>
function Comparability(const AName: string; const AIndex: ISymbolIndex; const AUnit: TUnitIndex;
  out ATarget: string): TComparability;
var
  mSymbol: TIndexSymbol;
begin
  ATarget := '';
  if IsUncomparableText(AName) then
  begin
    Result := TComparability.Uncomparable;
  end
  else if (AName = '') or (Pos('<', AName) > 0) or
    not FindType(AName.Substring(AName.LastIndexOf('.') + 1), AIndex, AUnit, mSymbol) then
  begin
    Result := TComparability.Comparable;
  end
  else if mSymbol.Kind = TIndexSymbolKind.RecordType then
  begin
    Result := TComparability.Uncomparable;
  end
  else if mSymbol.Kind <> TIndexSymbolKind.TypeAlias then
  begin
    Result := TComparability.Comparable;
  end
  else
  begin
    ATarget := AliasTarget(mSymbol.Signature);
    Result := TComparability.Alias;
    if ATarget = '' then
    begin
      Result := TComparability.Comparable;
    end;
  end;
end;

class function TAccessorCreation.IsComparable(const ATypeName: string; const AIndex: ISymbolIndex;
  const AUnit: TUnitIndex): Boolean;
var
  mName, mTarget: string;
  mLevel: Integer;
begin
  mName := Trim(ATypeName);
  for mLevel := 1 to 3 do
  begin
    case Comparability(mName, AIndex, AUnit, mTarget) of
      TComparability.Comparable:
        Exit(True);
      TComparability.Uncomparable:
        Exit(False);
    else
      mName := mTarget;
    end;
  end;
  Result := True;
end;

/// <summary>Rumpf der Klasse AClass; nil ohne.</summary>
function BodyOfClass(ASource: TCommandSource; const AClass: TIndexSymbol): TSyntaxNode;
begin
  Result := TRoutineBody.TypeBody(ASource.Tree.Root, AClass.Name.Substring(AClass.Name.LastIndexOf('.') + 1));
end;

/// <summary>Erster Abschnitt AName (oder "strict AName") im Klassenrumpf; nil ohne.</summary>
function SectionNode(ABody: TSyntaxNode; const AName: string; out ANext: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  Result := nil;
  ANext := nil;
  for Index := 0 to ABody.ChildCount - 1 do
  begin
    if ABody[Index].Kind = TSyntaxKind.Visibility then
    begin
      if Result = nil then
      begin
        if SameText(ABody[Index].Name, AName) or SameText(ABody[Index].Name, 'strict ' + AName) then
        begin
          Result := ABody[Index];
        end;
      end
      else if ANext = nil then
      begin
        ANext := ABody[Index];
      end;
    end;
  end;
end;

function HasSection(ABody: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to ABody.ChildCount - 1 do
  begin
    if (ABody[Index].Kind = TSyntaxKind.Visibility) and SameText(ABody[Index].Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

type
  /// <summary>Die Klasse, in die eingefügt wird: Quelle, Klassensymbol und Klassenrumpf.</summary>
  TAccessorTarget = record
    Source: TCommandSource;
    ClassSymbol: TIndexSymbol;
    Body: TSyntaxNode;
  end;

/// <summary>Letztes Feld direkt hinter dem Abschnittskopf ASection; nil ohne. Die Mitglieder folgen dem
/// Abschnittskopf als Geschwister im Klassenrumpf.</summary>
function LastLeadingField(ABody, ASection: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := nil;
  mIndex := 0;
  while (mIndex < ABody.ChildCount) and (ABody[mIndex] <> ASection) do
  begin
    Inc(mIndex);
  end;
  for mIndex := mIndex + 1 to ABody.ChildCount - 1 do
  begin
    mChild := ABody[mIndex];
    if not (mChild.Kind in [TSyntaxKind.Field, TSyntaxKind.VarSection, TSyntaxKind.VarDecl]) then
    begin
      Break;
    end;
    Result := mChild;
  end;
end;

/// <summary>Einfügung der Zeile ALine (mit Einrückung) in den vorhandenen Abschnitt ASection vor der
/// Eigenschaft. Felder kommen hinter die Felder am Anfang des Abschnitts (Felder nach Methoden wären E2169),
/// Methoden ans Ende des Abschnitts bzw. direkt vor die Eigenschaft, wenn sie selbst darin steht.</summary>
function PlacementInSection(const ATarget: TAccessorTarget; ASection, ANext: TSyntaxNode; const ALine: string;
  AIsField: Boolean): TTextEdit;
var
  mLastField: TSyntaxNode;
  mSectionEnd: Integer;
begin
  if AIsField then
  begin
    mLastField := LastLeadingField(ATarget.Body, ASection);
    if mLastField <> nil then
    begin
      Exit(ATarget.Source.AfterLine(mLastField.EndPos.Line, ALine));
    end;
    Exit(ATarget.Source.AfterLine(ASection.StartPos.Line, ALine));
  end;
  mSectionEnd := ATarget.ClassSymbol.Range.EndPos.Line;
  if ANext <> nil then
  begin
    mSectionEnd := ANext.StartPos.Line;
  end;
  // Steht die Eigenschaft selbst im Abschnitt, direkt vor sie.
  Result := ATarget.Source.BeforeLine(Min(mSectionEnd, ATarget.Source.Line), ALine);
end;

/// <summary>Einfügung der Deklaration ADecl (ohne Einrückung) in den Abschnitt ASection vor der Eigenschaft.
/// ANewBlock: Es gab keinen passenden Abschnitt davor; die Einfügung beginnt dann mit ASection, und der Aufrufer
/// setzt danach den Abschnitt der Eigenschaft fort.</summary>
function Placement(const ATarget: TAccessorTarget; const ASection, ADecl: string; AIsField: Boolean;
  out ANewBlock: Boolean): TTextEdit;
var
  mSection, mNext: TSyntaxNode;
  mPropertyLine: Integer;
  mIndent: string;
begin
  mPropertyLine := ATarget.Source.Line;
  mIndent := ATarget.Source.Indent(mPropertyLine);
  mSection := SectionNode(ATarget.Body, ASection, mNext);
  ANewBlock := (mSection = nil) or (mSection.StartPos.Line >= mPropertyLine);
  if not ANewBlock then
  begin
    Exit(PlacementInSection(ATarget, mSection, mNext, mIndent + ADecl, AIsField));
  end;
  Result := ATarget.Source.BeforeLine(mPropertyLine, ATarget.Source.Indent(ATarget.ClassSymbol.Range.EndPos.Line) +
    ASection + ATarget.Source.LineBreak + mIndent + ADecl);
end;

/// <summary>Beginnen beide Einfügungen am Anfang derselben Zeile?</summary>
function SameLineStart(const AFirst, ASecond: TTextEdit): Boolean;
begin
  Result := (AFirst.Range.StartPos.Line = ASecond.Range.StartPos.Line) and
    (AFirst.Range.StartPos.Character = ASecond.Range.StartPos.Character) and (ASecond.Range.StartPos.Character = 0);
end;

/// <summary>Text der Einfügung AIndex zum Anhängen an die Einfügung davor: Beginnt sie denselben neuen Abschnitt
/// wie die Einfügung davor, ohne den Kopf.</summary>
function AppendedText(const AEdits: TArray<TTextEdit>; const ANewBlocks: TArray<Boolean>;
  const ASections: TArray<string>; AIndex: Integer; const AHeader: string): string;
begin
  Result := AEdits[AIndex].NewText;
  if (AIndex > 0) and ANewBlocks[AIndex] and ANewBlocks[AIndex - 1] and
    SameText(ASections[AIndex - 1], ASections[AIndex]) and StartsStr(AHeader, Result) then
  begin
    Result := Copy(Result, Length(AHeader) + 1, MaxInt);
  end;
end;

/// <summary>Setzt hinter Einfügungen direkt vor der Eigenschaft deren Abschnitt fort.</summary>
procedure ContinueSection(ASource: TCommandSource; const AClass: TIndexSymbol; var AEdits: TArray<TTextEdit>);
var
  mIndex: Integer;
  mCurrent, mClassIndent: string;
begin
  mClassIndent := ASource.Indent(AClass.Range.EndPos.Line);
  mCurrent := TInterfaceStubs.LastSection(ASource.Tree.Tokens, AClass.Range.StartPos.Line, ASource.Line);
  if mCurrent = '' then
  begin
    mCurrent := 'public';
  end;
  for mIndex := 0 to High(AEdits) do
  begin
    if (AEdits[mIndex].Range.StartPos.Line = ASource.Line) and (AEdits[mIndex].Range.StartPos.Character = 0) then
    begin
      AEdits[mIndex].NewText := AEdits[mIndex].NewText + mClassIndent + mCurrent + ASource.LineBreak;
    end;
  end;
end;

/// <summary>Legt Einfügungen an derselben Stelle zusammen (in Reihenfolge), ohne einen Abschnittskopf zu
/// wiederholen, und setzt nach neuen Abschnitten vor der Eigenschaft deren Abschnitt fort.</summary>
function Merged(ASource: TCommandSource; const AClass: TIndexSymbol; const AEdits: TArray<TTextEdit>;
  const ANewBlocks: TArray<Boolean>; const ASections: TArray<string>): TArray<TTextEdit>;
var
  mIndex, mLast: Integer;
  mClassIndent: string;
  mAnyNew: Boolean;
begin
  Result := nil;
  mClassIndent := ASource.Indent(AClass.Range.EndPos.Line);
  mAnyNew := False;
  mLast := -1;
  for mIndex := 0 to High(AEdits) do
  begin
    mAnyNew := mAnyNew or ANewBlocks[mIndex];
    if (mLast >= 0) and SameLineStart(Result[mLast], AEdits[mIndex]) then
    begin
      Result[mLast].NewText := Result[mLast].NewText + AppendedText(AEdits, ANewBlocks, ASections, mIndex,
        mClassIndent + ASections[mIndex] + ASource.LineBreak);
      Continue;
    end;
    Result := Result + [AEdits[mIndex]];
    mLast := High(Result);
  end;
  if mAnyNew then
  begin
    ContinueSection(ASource, AClass, Result);
  end;
end;

/// <summary>Muss APlan das Feld mit anlegen? Ja beim Feld selbst und beim Setter ohne Feld und Index; der Setter
/// braucht das Feld, es steht vor der Methode.</summary>
function NeedsField(const APlan: TAccessorPlan; AHasField: Boolean): Boolean;
begin
  Result := (APlan.Kind = TAccessorKind.Field) or
    ((APlan.Kind = TAccessorKind.Setter) and not AHasField and (APlan.IndexParameters = ''));
end;

/// <summary>Deklarationen für APlan (Feld und/oder Methode), zusammengelegt.</summary>
function DeclarationEdits(const ATarget: TAccessorTarget; const APlan: TAccessorPlan; AHasField: Boolean;
  out AWithField: Boolean): TArray<TTextEdit>;
var
  mNewBlock: Boolean;
  mFieldSection: string;
  mField: TAccessorPlan;
  mPending: TArray<TTextEdit>;
  mNewBlocks: TArray<Boolean>;
  mSections: TArray<string>;
begin
  mFieldSection := 'private';
  if HasSection(ATarget.Body, 'strict private') then
  begin
    mFieldSection := 'strict private';
  end;
  mPending := nil;
  mNewBlocks := nil;
  mSections := nil;
  AWithField := False;
  if NeedsField(APlan, AHasField) then
  begin
    mField := APlan;
    mField.Kind := TAccessorKind.Field;
    mPending := mPending + [Placement(ATarget, mFieldSection, TAccessorCreation.Declaration(mField), True,
      mNewBlock)];
    mNewBlocks := mNewBlocks + [mNewBlock];
    mSections := mSections + [mFieldSection];
    AWithField := APlan.Kind = TAccessorKind.Setter;
  end;
  if APlan.Kind <> TAccessorKind.Field then
  begin
    mPending := mPending + [Placement(ATarget, APlan.MethodSection, TAccessorCreation.Declaration(APlan), False,
      mNewBlock)];
    mNewBlocks := mNewBlocks + [mNewBlock];
    mSections := mSections + [APlan.MethodSection];
  end;
  Result := Merged(ATarget.Source, ATarget.ClassSymbol, mPending, mNewBlocks, mSections);
end;

/// <summary>Getter: liefert das Feld, wenn es das gibt (ohne Index), sonst Default(Typ).</summary>
function GetterText(const ATarget: TAccessorTarget; const APlan: TAccessorPlan; AHasField: Boolean): string;
var
  mParams, mLB, mValue: string;
begin
  mLB := ATarget.Source.LineBreak;
  mParams := '';
  if APlan.IndexParameters <> '' then
  begin
    mParams := '(' + APlan.IndexParameters + ')';
  end;
  mValue := 'Default(' + APlan.PropertyType + ')';
  if AHasField and (APlan.IndexParameters = '') then
  begin
    mValue := APlan.FieldName;
  end;
  Result := Format('function %s.%s%s: %s;', [ATarget.ClassSymbol.Name, APlan.Name, mParams, APlan.PropertyType]) +
    mLB + 'begin' + mLB + '  Result := ' + mValue + ';' + mLB + 'end;';
end;

/// <summary>Setter: leer mit Index, sonst mit Änderungsprüfung wie /prop bzw. ohne bei nicht vergleichbaren
/// Typen.</summary>
function SetterText(const ATarget: TAccessorTarget; const AIndex: ISymbolIndex; const APlan: TAccessorPlan): string;
var
  mHead, mLB: string;
begin
  mLB := ATarget.Source.LineBreak;
  mHead := 'procedure ' + ATarget.ClassSymbol.Name + '.' +
    Copy(TAccessorCreation.Declaration(APlan), Length('procedure ') + 1, MaxInt);
  if APlan.IndexParameters <> '' then
  begin
    Result := mHead + mLB + 'begin' + mLB + 'end;';
  end
  else if TAccessorCreation.IsComparable(APlan.PropertyType, AIndex, ATarget.Source.UnitIndex) then
  begin
    Result := mHead + mLB + TSetterGenerator.Body(APlan.FieldName, 'Value',
      TSetterGenerator.NotifyCall(ATarget.Source, AIndex, ATarget.ClassSymbol), mLB);
  end
  else
  begin
    Result := mHead + mLB + 'begin' + mLB + '  ' + APlan.FieldName + ' := Value;' + mLB + 'end;';
  end;
end;

class function TAccessorCreation.Edits(ASource: TCommandSource; const AIndex: ISymbolIndex;
  const AClass: TIndexSymbol; const APlan: TAccessorPlan; out AEdits: TArray<TTextEdit>;
  out AWithField: Boolean): Boolean;
var
  mTarget: TAccessorTarget;
  mMember: TIndexSymbol;
  mHasField: Boolean;
begin
  AEdits := nil;
  AWithField := False;
  mTarget.Source := ASource;
  mTarget.ClassSymbol := AClass;
  mTarget.Body := BodyOfClass(ASource, AClass);
  Result := (mTarget.Body <> nil) and not FindMember(ASource, AClass, APlan.Name, [TIndexSymbolKind.Field,
    TIndexSymbolKind.Method, TIndexSymbolKind.Property_], mMember) and
    not ((APlan.Kind = TAccessorKind.Field) and (APlan.IndexParameters <> ''));
  if not Result then
  begin
    Exit;
  end;
  mHasField := FindMember(ASource, AClass, APlan.FieldName, [TIndexSymbolKind.Field], mMember);
  AEdits := DeclarationEdits(mTarget, APlan, mHasField, AWithField);
  if APlan.Kind = TAccessorKind.Getter then
  begin
    AEdits := AEdits + [ASource.AddBody(AClass.Name, GetterText(mTarget, APlan, mHasField))];
  end
  else if APlan.Kind = TAccessorKind.Setter then
  begin
    AEdits := AEdits + [ASource.AddBody(AClass.Name, SetterText(mTarget, AIndex, APlan))];
  end;
end;

end.
