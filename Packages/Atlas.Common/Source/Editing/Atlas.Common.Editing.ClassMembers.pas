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

function Ancestors(ASource: TCommandSource; const AIndex: ISymbolIndex; const AClassName: string): TArray<string>;
var
  Name, Next: string;
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
  Depth: Integer;
  Found: Boolean;
begin
  Result := nil;
  Name := AClassName;
  for Depth := 1 to 32 do
  begin
    Next := '';
    Found := False;
    for Symbol in ASource.UnitIndex.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.ClassType) and SameText(Symbol.Name, Name) and (Symbol.Container = '') then
      begin
        Found := True;
        if Length(Symbol.Ancestors) > 0 then
          Next := Symbol.Ancestors[0];
        Break;
      end;
    if not Found and (AIndex <> nil) then
      for Location in AIndex.FindSymbols(Name) do
        if Location.Symbol.Kind = TIndexSymbolKind.ClassType then
        begin
          if Length(Location.Symbol.Ancestors) > 0 then
            Next := Location.Symbol.Ancestors[0];
          Break;
        end;
    if (Next = '') or (IndexText(Next, Result) >= 0) then
      Exit;
    Result := Result + [Next];
    Name := Next;
  end;
end;

function DescendsFrom(const AChain: TArray<string>; const ARoots: array of string): Boolean;
var
  Name: string;
begin
  for Name in AChain do
    if MatchText(Name, ARoots) then
      Exit(True);
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
    if (Symbol.Kind in AKinds) and SameText(Symbol.Name, AName) and SameText(Symbol.Container, AClass.Name) and
      (Symbol.Range.StartPos.Line >= AClass.Range.StartPos.Line) and
      (Symbol.Range.EndPos.Line <= AClass.Range.EndPos.Line) then
    begin
      AMember := Symbol;
      Exit(True);
    end;
  Result := False;
end;

function Members(ASource: TCommandSource; const AClass: TIndexSymbol; AKinds: TMemberKinds): TArray<TIndexSymbol>;
var
  Symbol: TIndexSymbol;
begin
  Result := nil;
  for Symbol in ASource.UnitIndex.Symbols do
    if (Symbol.Kind in AKinds) and SameText(Symbol.Container, AClass.Name) and
      (Symbol.Range.StartPos.Line >= AClass.Range.StartPos.Line) and
      (Symbol.Range.EndPos.Line <= AClass.Range.EndPos.Line) then
      Result := Result + [Symbol];
end;

function FindBody(ASource: TCommandSource; const AClassName, AName: string): TSyntaxNode;
var
  Section: TSyntaxNode;
  Index: Integer;
begin
  Result := nil;
  Section := ASource.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Section = nil then
    Exit;
  for Index := 0 to Section.ChildCount - 1 do
    if (Section[Index].Kind = TSyntaxKind.RoutineDecl) and SameText(Section[Index].Name, AClassName + '.' + AName) and
      (Section[Index].FindChild(TSyntaxKind.Block) <> nil) then
      Exit(Section[Index]);
end;

function Accessor(const ADeclaration, AKeyword: string): string;
var
  Words: TArray<string>;
  Index: Integer;
begin
  Words := ADeclaration.Replace(';', ' ').Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  for Index := 0 to High(Words) - 1 do
    if SameText(Words[Index], AKeyword) then
      Exit(Words[Index + 1]);
  Result := '';
end;

function CreatedFields(ASource: TCommandSource; const AClassName: string): TArray<string>;
var
  Symbol: TIndexSymbol;
  Index, Assign: Integer;
  Line, Field: string;
begin
  Result := nil;
  for Symbol in ASource.UnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.Constructor_) and SameText(Symbol.Container, AClassName) and
      (Symbol.Range.EndPos.Line > Symbol.Range.StartPos.Line) then
      for Index := Symbol.Range.StartPos.Line to Symbol.Range.EndPos.Line do
      begin
        Line := Trim(ASource.Lines[Index]);
        Assign := Pos(':=', Line);
        if (Assign = 0) or (Pos('.Create', Copy(Line, Assign, MaxInt)) = 0) then
          Continue;
        Field := Trim(Copy(Line, 1, Assign - 1));
        if IsValidIdent(Field) and (IndexText(Field, Result) < 0) then
          Result := Result + [Field];
      end;
end;

{ TSetterGenerator }

class function TSetterGenerator.NotifyCall(ASource: TCommandSource; const AIndex: ISymbolIndex;
  const AClass: TIndexSymbol): string;
var
  Member: TIndexSymbol;
begin
  if DescendsFrom(Ancestors(ASource, AIndex, AClass.Name), ControlRoots) then
    Result := 'Invalidate'
  else if FindMember(ASource, AClass, 'Changed', [TIndexSymbolKind.Method], Member) then
    Result := 'Changed'
  else if FindMember(ASource, AClass, 'DoChange', [TIndexSymbolKind.Method], Member) then
    Result := 'DoChange'
  else
    Result := '';
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
    Result := Result + ALineBreak + '  ' + Line;
  Result := Result + ALineBreak + 'end;';
end;

end.
