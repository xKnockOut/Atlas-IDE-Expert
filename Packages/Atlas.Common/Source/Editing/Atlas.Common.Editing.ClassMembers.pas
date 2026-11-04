unit Atlas.Common.Editing.ClassMembers;

// Gemeinsame Bausteine für Klassenmitglieder: Vorfahren, Mitglieder und Rümpfe
// einer Klasse in der Unit und der Setter mit Änderungsprüfung. Die Schnellbefehle
// /prop und /changed (#294, #320) und die kontextabhängigen Code-Vorlagen der
// Vervollständigung (#51) nutzen denselben Erzeuger, damit das Ergebnis gleich
// aussieht:
//
//   if FName <> Value then
//   begin
//     FName := Value;
//     Invalidate;
//   end;
//
// Benachrichtigt wird mit Invalidate bei Controls, sonst mit Changed bzw. DoChange,
// wenn die Klasse sie deklariert; ohne beides bleibt es bei der Prüfung.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.CommandSource;

type
  TMemberKinds = set of TIndexSymbolKind;

const
  ComponentRoots: array[0..13] of string = ('TComponent', 'TControl', 'TWinControl', 'TCustomControl',
    'TGraphicControl', 'TForm', 'TCustomForm', 'TFrame', 'TCustomFrame', 'TDataModule', 'TDataSet', 'TCustomPanel',
    'TPanel', 'TCustomConnection');
  ControlRoots: array[0..9] of string = ('TControl', 'TWinControl', 'TCustomControl', 'TGraphicControl', 'TForm',
    'TCustomForm', 'TFrame', 'TCustomFrame', 'TCustomPanel', 'TPanel');

/// <summary>Vorfahren von AClassName, soweit Unit und Index sie kennen; der erste ist der direkte.</summary>
function Ancestors(ASource: TCommandSource; const AIndex: ISymbolIndex; const AClassName: string): TArray<string>;
function DescendsFrom(const AChain: TArray<string>; const ARoots: array of string): Boolean;
/// <summary>ATypeName ist TComponent oder stammt davon ab.</summary>
function IsComponentType(ASource: TCommandSource; const AIndex: ISymbolIndex; const ATypeName: string): Boolean;
/// <summary>Mitglied AName der Klasse AClass in der Unit (Feld, Property, Methode).</summary>
function FindMember(ASource: TCommandSource; const AClass: TIndexSymbol; const AName: string;
  AKinds: TMemberKinds; out AMember: TIndexSymbol): Boolean;
/// <summary>Mitglieder der Klasse AClass in der Unit mit einer Art aus AKinds, in Textreihenfolge.</summary>
function Members(ASource: TCommandSource; const AClass: TIndexSymbol; AKinds: TMemberKinds): TArray<TIndexSymbol>;
/// <summary>Rumpf TKlasse.AName in der implementation; nil ohne.</summary>
function FindBody(ASource: TCommandSource; const AClassName, AName: string): TSyntaxNode;
/// <summary>Wort hinter AKeyword in einer Property-Deklaration ("read FName" → FName); '' ohne.</summary>
function Accessor(const ADeclaration, AKeyword: string): string;
/// <summary>Felder, die in Konstruktoren von AClassName mit FName := ….Create erzeugt werden.</summary>
function CreatedFields(ASource: TCommandSource; const AClassName: string): TArray<string>;

type
  /// <summary>Setter mit Änderungsprüfung (#51, #320).</summary>
  TSetterGenerator = class
  public
    /// <summary>Invalidate bei Controls, Changed bzw. DoChange, wenn AClass sie deklariert; sonst ''.</summary>
    class function NotifyCall(ASource: TCommandSource; const AIndex: ISymbolIndex;
      const AClass: TIndexSymbol): string; static;
    /// <summary>Anweisungen ohne Einrückung: Prüfung, Zuweisung und ACall in begin/end; ohne ACall nur Prüfung
    /// und Zuweisung.</summary>
    class function Statements(const AField, AValue, ACall: string): TArray<string>; static;
    /// <summary>Rumpf "begin … end;" auf Spalte 0 mit Zeilenumbruch ALineBreak, ohne Umbruch am Ende.</summary>
    class function Body(const AField, AValue, ACall, ALineBreak: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

/// <summary>Erster Vorfahr von ASymbol; '' ohne.</summary>
function FirstOf(const ASymbol: TIndexSymbol): string;
begin
  Result := '';
  if Length(ASymbol.Ancestors) > 0 then
  begin
    Result := ASymbol.Ancestors[0];
  end;
end;

/// <summary>Erster Vorfahr der Klasse AName; '' ohne oder wenn sie weder in der Unit noch im Index steht. Die
/// eigene Unit geht vor.</summary>
function FirstAncestor(ASource: TCommandSource; const AIndex: ISymbolIndex; const AName: string): string;
var
  mSymbol: TIndexSymbol;
  mLocation: TSymbolLocation;
begin
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and SameText(mSymbol.Name, AName) and (mSymbol.Container = '') then
    begin
      Exit(FirstOf(mSymbol));
    end;
  end;
  if AIndex <> nil then
  begin
    for mLocation in AIndex.FindSymbols(AName) do
    begin
      if mLocation.Symbol.Kind = TIndexSymbolKind.ClassType then
      begin
        Exit(FirstOf(mLocation.Symbol));
      end;
    end;
  end;
  Result := '';
end;

function Ancestors(ASource: TCommandSource; const AIndex: ISymbolIndex; const AClassName: string): TArray<string>;
var
  mName, mNext: string;
  mDepth: Integer;
begin
  Result := nil;
  mName := AClassName;
  for mDepth := 1 to 32 do
  begin
    mNext := FirstAncestor(ASource, AIndex, mName);
    if (mNext = '') or (IndexText(mNext, Result) >= 0) then
    begin
      Exit;
    end;
    Result := Result + [mNext];
    mName := mNext;
  end;
end;

function DescendsFrom(const AChain: TArray<string>; const ARoots: array of string): Boolean;
var
  Name: string;
begin
  for Name in AChain do
  begin
    if MatchText(Name, ARoots) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function IsComponentType(ASource: TCommandSource; const AIndex: ISymbolIndex; const ATypeName: string): Boolean;
begin
  Result := MatchText(ATypeName, ComponentRoots) or
    DescendsFrom(Ancestors(ASource, AIndex, ATypeName), ComponentRoots);
end;

function FindMember(ASource: TCommandSource; const AClass: TIndexSymbol; const AName: string;
  AKinds: TMemberKinds; out AMember: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in ASource.UnitIndex.Symbols do
  begin
    if (Symbol.Kind in AKinds) and SameText(Symbol.Name, AName) and SameText(Symbol.Container, AClass.Name) and
      (Symbol.Range.StartPos.Line >= AClass.Range.StartPos.Line) and
      (Symbol.Range.EndPos.Line <= AClass.Range.EndPos.Line) then
    begin
      AMember := Symbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

function Members(ASource: TCommandSource; const AClass: TIndexSymbol; AKinds: TMemberKinds): TArray<TIndexSymbol>;
var
  Symbol: TIndexSymbol;
begin
  Result := nil;
  for Symbol in ASource.UnitIndex.Symbols do
  begin
    if (Symbol.Kind in AKinds) and SameText(Symbol.Container, AClass.Name) and
      (Symbol.Range.StartPos.Line >= AClass.Range.StartPos.Line) and
      (Symbol.Range.EndPos.Line <= AClass.Range.EndPos.Line) then
    begin
      Result := Result + [Symbol];
    end;
  end;
end;

function FindBody(ASource: TCommandSource; const AClassName, AName: string): TSyntaxNode;
var
  Section: TSyntaxNode;
  Index: Integer;
begin
  Result := nil;
  Section := ASource.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Section = nil then
  begin
    Exit;
  end;
  for Index := 0 to Section.ChildCount - 1 do
  begin
    if (Section[Index].Kind = TSyntaxKind.RoutineDecl) and SameText(Section[Index].Name, AClassName + '.' + AName) and
      (Section[Index].FindChild(TSyntaxKind.Block) <> nil) then
    begin
      Exit(Section[Index]);
    end;
  end;
end;

function Accessor(const ADeclaration, AKeyword: string): string;
var
  Words: TArray<string>;
  Index: Integer;
begin
  Words := ADeclaration.Replace(';', ' ').Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  for Index := 0 to High(Words) - 1 do
  begin
    if SameText(Words[Index], AKeyword) then
    begin
      Exit(Words[Index + 1]);
    end;
  end;
  Result := '';
end;

/// <summary>Feld, dem die Zeile ALine ein neues Objekt zuweist ("FListe := TList.Create"); '' sonst.</summary>
function CreatedField(const ALine: string): string;
var
  mLine: string;
  mAssign: Integer;
begin
  Result := '';
  mLine := Trim(ALine);
  mAssign := Pos(':=', mLine);
  if (mAssign > 0) and (Pos('.Create', Copy(mLine, mAssign, MaxInt)) > 0) then
  begin
    Result := Trim(Copy(mLine, 1, mAssign - 1));
  end;
end;

/// <summary>Ist ASymbol ein Konstruktor der Klasse AClassName mit Rumpf über mehrere Zeilen?</summary>
function IsConstructorOf(const ASymbol: TIndexSymbol; const AClassName: string): Boolean;
begin
  Result := (ASymbol.Kind = TIndexSymbolKind.Constructor_) and SameText(ASymbol.Container, AClassName) and
    (ASymbol.Range.EndPos.Line > ASymbol.Range.StartPos.Line);
end;

function CreatedFields(ASource: TCommandSource; const AClassName: string): TArray<string>;
var
  mSymbol: TIndexSymbol;
  mIndex: Integer;
  mField: string;
begin
  Result := nil;
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if not IsConstructorOf(mSymbol, AClassName) then
    begin
      Continue;
    end;
    for mIndex := mSymbol.Range.StartPos.Line to mSymbol.Range.EndPos.Line do
    begin
      mField := CreatedField(ASource.Lines[mIndex]);
      if IsValidIdent(mField) and (IndexText(mField, Result) < 0) then
      begin
        Result := Result + [mField];
      end;
    end;
  end;
end;

{ TSetterGenerator }

class function TSetterGenerator.NotifyCall(ASource: TCommandSource; const AIndex: ISymbolIndex;
  const AClass: TIndexSymbol): string;
var
  Member: TIndexSymbol;
begin
  if DescendsFrom(Ancestors(ASource, AIndex, AClass.Name), ControlRoots) then
  begin
    Result := 'Invalidate';
  end
  else if FindMember(ASource, AClass, 'Changed', [TIndexSymbolKind.Method], Member) then
  begin
    Result := 'Changed';
  end
  else if FindMember(ASource, AClass, 'DoChange', [TIndexSymbolKind.Method], Member) then
  begin
    Result := 'DoChange';
  end
  else
  begin
    Result := '';
  end;
end;

class function TSetterGenerator.Statements(const AField, AValue, ACall: string): TArray<string>;
begin
  if ACall = '' then
    begin Result := [Format('if %s <> %s then', [AField, AValue]), Format('  %s := %s;', [AField, AValue])]; Exit; end;
  Result := [Format('if %s <> %s then', [AField, AValue]), 'begin', Format('  %s := %s;', [AField, AValue]),
    Format('  %s;', [ACall]), 'end;'];
end;

class function TSetterGenerator.Body(const AField, AValue, ACall, ALineBreak: string): string;
var
  Line: string;
begin
  Result := 'begin';
  for Line in Statements(AField, AValue, ACall) do
  begin
    Result := Result + ALineBreak + '  ' + Line;
  end;
  Result := Result + ALineBreak + 'end;';
end;

end.
