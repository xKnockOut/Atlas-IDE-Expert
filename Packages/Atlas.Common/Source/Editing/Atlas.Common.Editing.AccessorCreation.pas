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
          Result := Result + '(' + APlan.IndexParameters + ')';
        Result := Result + ': ' + APlan.PropertyType + ';';
      end;
    TAccessorKind.Setter:
      begin
        Index := '';
        if APlan.IndexParameters <> '' then
          Index := APlan.IndexParameters + '; ';
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
    if IsTypeSymbol(Symbol, AName) then
    begin
      ASymbol := Symbol;
      Exit(True);
    end;
  if AIndex <> nil then
    for Location in AIndex.FindSymbols(AName) do
      if IsTypeSymbol(Location.Symbol, AName) then
      begin
        ASymbol := Location.Symbol;
        Exit(True);
      end;
  ASymbol := Default(TIndexSymbol);
  Result := False;
end;

class function TAccessorCreation.IsComparable(const ATypeName: string; const AIndex: ISymbolIndex;
  const AUnit: TUnitIndex): Boolean;
var
  Name, Right: string;
  Level: Integer;
  Symbol: TIndexSymbol;
begin
  Name := Trim(ATypeName);
  for Level := 1 to 3 do
  begin
    if StartsText('array', Name) or StartsText('TArray<', Name) or SameText(Name, 'TBytes') or
      StartsText('procedure', Name) or StartsText('function', Name) or StartsText('reference', Name) or
      StartsText('record', Name) then
      Exit(False);
    if (Name = '') or (Pos('<', Name) > 0) or
      not FindType(Name.Substring(Name.LastIndexOf('.') + 1), AIndex, AUnit, Symbol) then
      Exit(True);
    if Symbol.Kind = TIndexSymbolKind.RecordType then
      Exit(False);
    if Symbol.Kind <> TIndexSymbolKind.TypeAlias then
      Exit(True);
    // "TNotifyEvent = procedure(Sender: TObject) of object", "TPunkte = array of TPunkt", "TName = string".
    Right := Symbol.Signature;
    if Pos('=', Right) > 0 then
      Right := Trim(Copy(Right, Pos('=', Right) + 1, MaxInt));
    if StartsText('type ', Right) then
      Right := Trim(Copy(Right, 6, MaxInt));
    if Right = '' then
      Exit(True);
    Name := Right;
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
    if ABody[Index].Kind = TSyntaxKind.Visibility then
      if Result = nil then
      begin
        if SameText(ABody[Index].Name, AName) or SameText(ABody[Index].Name, 'strict ' + AName) then
          Result := ABody[Index];
      end
      else if ANext = nil then
        ANext := ABody[Index];
end;

function HasSection(ABody: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to ABody.ChildCount - 1 do
    if (ABody[Index].Kind = TSyntaxKind.Visibility) and SameText(ABody[Index].Name, AName) then
      Exit(True);
  Result := False;
end;

/// <summary>Einfügung der Deklaration ADecl (ohne Einrückung) in den Abschnitt ASection vor der Eigenschaft.
/// ANewBlock: Es gab keinen passenden Abschnitt davor; die Einfügung beginnt dann mit ASection, und der Aufrufer
/// setzt danach den Abschnitt der Eigenschaft fort.</summary>
function Placement(ASource: TCommandSource; const AClass: TIndexSymbol; ABody: TSyntaxNode;
  const ASection, ADecl: string; AIsField: Boolean; out ANewBlock: Boolean): TTextEdit;
var
  Section, Next, Child, LastField: TSyntaxNode;
  Index, PropertyLine, SectionEnd: Integer;
  Indent: string;
begin
  ANewBlock := False;
  PropertyLine := ASource.Line;
  Indent := ASource.Indent(PropertyLine);
  Section := SectionNode(ABody, ASection, Next);
  if (Section <> nil) and (Section.StartPos.Line < PropertyLine) then
  begin
    if AIsField then
    begin
      // Hinter die Felder am Anfang des Abschnitts; Felder nach Methoden wären E2169. Die Mitglieder folgen dem
      // Abschnittskopf als Geschwister im Klassenrumpf.
      LastField := nil;
      Index := 0;
      while (Index < ABody.ChildCount) and (ABody[Index] <> Section) do
        Inc(Index);
      for Index := Index + 1 to ABody.ChildCount - 1 do
      begin
        Child := ABody[Index];
        if not (Child.Kind in [TSyntaxKind.Field, TSyntaxKind.VarSection, TSyntaxKind.VarDecl]) then
          Break;
        LastField := Child;
      end;
      if LastField <> nil then
        Exit(ASource.AfterLine(LastField.EndPos.Line, Indent + ADecl));
      Exit(ASource.AfterLine(Section.StartPos.Line, Indent + ADecl));
    end;
    if Next <> nil then
      SectionEnd := Next.StartPos.Line
    else
      SectionEnd := AClass.Range.EndPos.Line;
    if SectionEnd <= PropertyLine then
      Exit(ASource.BeforeLine(SectionEnd, Indent + ADecl));
    // Die Eigenschaft steht selbst im Abschnitt.
    Exit(ASource.BeforeLine(PropertyLine, Indent + ADecl));
  end;
  ANewBlock := True;
  Result := ASource.BeforeLine(PropertyLine, ASource.Indent(AClass.Range.EndPos.Line) + ASection + ASource.LineBreak +
    Indent + ADecl);
end;

/// <summary>Legt Einfügungen an derselben Stelle zusammen (in Reihenfolge), ohne einen Abschnittskopf zu
/// wiederholen, und setzt nach neuen Abschnitten vor der Eigenschaft deren Abschnitt fort.</summary>
function Merged(ASource: TCommandSource; const AClass: TIndexSymbol; const AEdits: TArray<TTextEdit>;
  const ANewBlocks: TArray<Boolean>; const ASections: TArray<string>): TArray<TTextEdit>;
var
  Index, Last: Integer;
  Text, Header, Current, ClassIndent: string;
  AnyNew: Boolean;
begin
  Result := nil;
  ClassIndent := ASource.Indent(AClass.Range.EndPos.Line);
  AnyNew := False;
  Last := -1;
  for Index := 0 to High(AEdits) do
  begin
    AnyNew := AnyNew or ANewBlocks[Index];
    if (Last >= 0) and (Result[Last].Range.StartPos.Line = AEdits[Index].Range.StartPos.Line) and
      (Result[Last].Range.StartPos.Character = AEdits[Index].Range.StartPos.Character) and
      (AEdits[Index].Range.StartPos.Character = 0) then
    begin
      Text := AEdits[Index].NewText;
      Header := ClassIndent + ASections[Index] + ASource.LineBreak;
      // Gleicher neuer Abschnitt wie die Einfügung davor: Kopf nur einmal.
      if ANewBlocks[Index] and (Index > 0) and ANewBlocks[Index - 1] and SameText(ASections[Index - 1],
        ASections[Index]) and StartsStr(Header, Text) then
        Text := Copy(Text, Length(Header) + 1, MaxInt);
      Result[Last].NewText := Result[Last].NewText + Text;
      Continue;
    end;
    Result := Result + [AEdits[Index]];
    Last := High(Result);
  end;
  if not AnyNew then
    Exit;
  Current := TInterfaceStubs.LastSection(ASource.Tree.Tokens, AClass.Range.StartPos.Line, ASource.Line);
  if Current = '' then
    Current := 'public';
  for Index := 0 to High(Result) do
    if (Result[Index].Range.StartPos.Line = ASource.Line) and (Result[Index].Range.StartPos.Character = 0) then
      Result[Index].NewText := Result[Index].NewText + ClassIndent + Current + ASource.LineBreak;
end;

class function TAccessorCreation.Edits(ASource: TCommandSource; const AIndex: ISymbolIndex;
  const AClass: TIndexSymbol; const APlan: TAccessorPlan; out AEdits: TArray<TTextEdit>;
  out AWithField: Boolean): Boolean;
var
  Body: TSyntaxNode;
  Member: TIndexSymbol;
  HasField, NewBlock: Boolean;
  FieldSection, LB, Head, Text, Params: string;
  Field: TAccessorPlan;
  Pending: TArray<TTextEdit>;
  NewBlocks: TArray<Boolean>;
  Sections: TArray<string>;
begin
  AEdits := nil;
  AWithField := False;
  Result := False;
  Body := BodyOfClass(ASource, AClass);
  if (Body = nil) or FindMember(ASource, AClass, APlan.Name, [TIndexSymbolKind.Field, TIndexSymbolKind.Method,
    TIndexSymbolKind.Property_], Member) then
    Exit;
  if (APlan.Kind = TAccessorKind.Field) and (APlan.IndexParameters <> '') then
    Exit;
  FieldSection := 'private';
  if HasSection(Body, 'strict private') then
    FieldSection := 'strict private';
  LB := ASource.LineBreak;
  HasField := FindMember(ASource, AClass, APlan.FieldName, [TIndexSymbolKind.Field], Member);
  Pending := nil;
  NewBlocks := nil;
  Sections := nil;
  // Der Setter braucht das Feld; es steht vor der Methode.
  if (APlan.Kind = TAccessorKind.Field) or ((APlan.Kind = TAccessorKind.Setter) and not HasField and
    (APlan.IndexParameters = '')) then
  begin
    Field := APlan;
    Field.Kind := TAccessorKind.Field;
    Pending := Pending + [Placement(ASource, AClass, Body, FieldSection, Declaration(Field), True, NewBlock)];
    NewBlocks := NewBlocks + [NewBlock];
    Sections := Sections + [FieldSection];
    AWithField := APlan.Kind = TAccessorKind.Setter;
  end;
  if APlan.Kind <> TAccessorKind.Field then
  begin
    Pending := Pending + [Placement(ASource, AClass, Body, APlan.MethodSection, Declaration(APlan), False, NewBlock)];
    NewBlocks := NewBlocks + [NewBlock];
    Sections := Sections + [APlan.MethodSection];
  end;
  AEdits := Merged(ASource, AClass, Pending, NewBlocks, Sections);
  if APlan.Kind = TAccessorKind.Field then
    Exit(True);
  Params := '';
  if APlan.IndexParameters <> '' then
    Params := '(' + APlan.IndexParameters + ')';
  if APlan.Kind = TAccessorKind.Getter then
  begin
    Head := Format('function %s.%s%s: %s;', [AClass.Name, APlan.Name, Params, APlan.PropertyType]);
    if HasField and (APlan.IndexParameters = '') then
      Text := Head + LB + 'begin' + LB + '  Result := ' + APlan.FieldName + ';' + LB + 'end;'
    else
      Text := Head + LB + 'begin' + LB + '  Result := Default(' + APlan.PropertyType + ');' + LB + 'end;';
  end
  else
  begin
    Head := 'procedure ' + AClass.Name + '.' + Copy(Declaration(APlan), Length('procedure ') + 1, MaxInt);
    if APlan.IndexParameters <> '' then
      Text := Head + LB + 'begin' + LB + 'end;'
    else if IsComparable(APlan.PropertyType, AIndex, ASource.UnitIndex) then
      Text := Head + LB + TSetterGenerator.Body(APlan.FieldName, 'Value',
        TSetterGenerator.NotifyCall(ASource, AIndex, AClass), LB)
    else
      Text := Head + LB + 'begin' + LB + '  ' + APlan.FieldName + ' := Value;' + LB + 'end;';
  end;
  AEdits := AEdits + [ASource.AddBody(AClass.Name, Text)];
  Result := True;
end;

end.
