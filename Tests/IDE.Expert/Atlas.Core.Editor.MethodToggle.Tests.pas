unit Atlas.Core.Editor.MethodToggle.Tests;

// Tests für den Wechsel zwischen Deklaration und Implementierung (#775).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasMethodToggleTests = class
  public
    [Test]
    procedure DeclarationJumpsToImplementationAndBack;
    [Test]
    procedure CaretAnywhereInBodyJumpsToDeclaration;
    [Test]
    procedure MultiLineHeadingCountsAsDeclaration;
    [Test]
    procedure OverloadsMatchByParameterTypes;
    [Test]
    procedure OverloadsWithDifferentCountMatchByCount;
    [Test]
    procedure NestedAndGenericTypes;
    [Test]
    procedure ClassMethodsConstructorsAndOperators;
    [Test]
    procedure StandaloneRoutinesInInterfaceAndForward;
    [Test]
    procedure LocalRoutinesBelongToOuterMethod;
    [Test]
    procedure ImplementationWithoutParameterList;
    [Test]
    procedure CommentsStringsAndDirectivesAreIgnored;
    [Test]
    procedure RecordsInterfacesAndPropertiesDoNotConfuse;
    [Test]
    procedure NoCounterpartOutsideOrForAbstract;
    [Test]
    procedure ProgramWithoutInterfaceSection;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.MethodToggle;

/// <summary>Text aus Zeilen, getrennt mit CR LF wie im Editor.</summary>
function Source(const ALines: array of string): string;
var
  Line: string;
begin
  Result := '';
  for Line in ALines do
    Result := Result + Line + #13#10;
end;

/// <summary>Ziel als "Zeile:Zeichen" (0-basiert) oder "-" ohne Gegenstück.</summary>
function Jump(const AText: string; ALine, ACharacter: Integer): string; overload;
var
  Target: TAtlasMethodPlace;
begin
  if TAtlasMethodToggle.Counterpart(AText, ALine, ACharacter, Target) then
    Result := IntToStr(Target.Line) + ':' + IntToStr(Target.Character)
  else
    Result := '-';
end;

/// <summary>Wie oben, Cursor am Zeilenanfang.</summary>
function Jump(const AText: string; ALine: Integer): string; overload;
begin
  Result := Jump(AText, ALine, 0);
end;

function SimpleUnit: string;
begin
  Result := Source([
    'unit Demo;',                                   // 0
    '',                                             // 1
    'interface',                                    // 2
    '',                                             // 3
    'type',                                         // 4
    '  TFoo = class(TObject)',                      // 5
    '  private',                                    // 6
    '    FValue: Integer;',                         // 7
    '  public',                                     // 8
    '    procedure Run;',                           // 9
    '    function Value: Integer; virtual;',        // 10
    '  end;',                                       // 11
    '',                                             // 12
    'implementation',                               // 13
    '',                                             // 14
    'procedure TFoo.Run;',                          // 15
    'begin',                                        // 16
    '  if FValue > 0 then',                         // 17
    '  begin',                                      // 18
    '    FValue := 0;',                             // 19
    '  end;',                                       // 20
    'end;',                                         // 21
    '',                                             // 22
    'function TFoo.Value: Integer;',                // 23
    'begin',                                        // 24
    '  Result := FValue;',                          // 25
    'end;',                                         // 26
    '',                                             // 27
    'end.']);                                       // 28
end;

procedure TAtlasMethodToggleTests.DeclarationJumpsToImplementationAndBack;
var
  Text: string;
begin
  Text := SimpleUnit;
  // Ziel ist der Methodenname, nicht der Typname davor.
  Assert.AreEqual('15:15', Jump(Text, 9, 6));
  Assert.AreEqual('9:14', Jump(Text, 15, 0));
  Assert.AreEqual('23:14', Jump(Text, 10, 30));
  Assert.AreEqual('10:13', Jump(Text, 23, 3));
end;

procedure TAtlasMethodToggleTests.CaretAnywhereInBodyJumpsToDeclaration;
var
  Text: string;
begin
  Text := SimpleUnit;
  Assert.AreEqual('9:14', Jump(Text, 19, 6));
  Assert.AreEqual('9:14', Jump(Text, 21, 0));
  Assert.AreEqual('10:13', Jump(Text, 25, 2));
  // Leerzeile zwischen den Methoden gehört zu keiner.
  Assert.AreEqual('-', Jump(Text, 22));
end;

procedure TAtlasMethodToggleTests.MultiLineHeadingCountsAsDeclaration;
var
  Text: string;
begin
  Text := Source([
    'unit Demo;',
    'interface',
    'type',
    '  TFoo = class',
    '    procedure Save(const AName: string;',
    '      AFlags: Integer); overload;',
    '      virtual;',
    '  end;',
    'implementation',
    'procedure TFoo.Save(const AName: string;',
    '  AFlags: Integer);',
    'begin',
    'end;',
    'end.']);
  Assert.AreEqual('9:15', Jump(Text, 5, 2));
  Assert.AreEqual('9:15', Jump(Text, 6, 6));
  Assert.AreEqual('4:14', Jump(Text, 10, 2));
end;

procedure TAtlasMethodToggleTests.OverloadsMatchByParameterTypes;
var
  Text: string;
begin
  Text := Source([
    'unit Demo;',                                              // 0
    'interface',                                               // 1
    'type',                                                    // 2
    '  TFoo = class',                                          // 3
    '    procedure Add(AValue: Integer); overload;',           // 4
    '    procedure Add(const AValue: string); overload;',      // 5
    '    procedure Add(AValue: TArray<Integer>); overload;',   // 6
    '  end;',                                                  // 7
    'implementation',                                          // 8
    'procedure TFoo.Add(AValue: TArray<Integer>);',            // 9
    'begin',                                                   // 10
    'end;',                                                    // 11
    'procedure TFoo.Add(const AValue: string);',               // 12
    'begin',                                                   // 13
    'end;',                                                    // 14
    'procedure TFoo.Add(AValue: Integer);',                    // 15
    'begin',                                                   // 16
    'end;',                                                    // 17
    'end.']);
  Assert.AreEqual('15:15', Jump(Text, 4, 4));
  Assert.AreEqual('12:15', Jump(Text, 5, 4));
  Assert.AreEqual('9:15', Jump(Text, 6, 4));
  Assert.AreEqual('6:14', Jump(Text, 10));
  Assert.AreEqual('5:14', Jump(Text, 13));
  Assert.AreEqual('4:14', Jump(Text, 16));
  // Überladung ohne Parameter neben einer mit Parametern.
  Text := Source([
    'unit Demo;',                                   // 0
    'interface',                                    // 1
    'type',                                         // 2
    '  TFoo = class',                               // 3
    '    procedure Show(const AAt: TPoint); overload;', // 4
    '    procedure Show; overload;',                // 5
    '  end;',                                       // 6
    'implementation',                               // 7
    'procedure TFoo.Show(const AAt: TPoint);',      // 8
    'begin',                                        // 9
    'end;',                                         // 10
    'procedure TFoo.Show;',                         // 11
    'begin',                                        // 12
    'end;',                                         // 13
    'end.']);
  Assert.AreEqual('11:15', Jump(Text, 5));
  Assert.AreEqual('8:15', Jump(Text, 4));
  Assert.AreEqual('5:14', Jump(Text, 12));
  Assert.AreEqual('4:14', Jump(Text, 9));
end;

procedure TAtlasMethodToggleTests.OverloadsWithDifferentCountMatchByCount;
var
  Text: string;
begin
  // Typ im Kopf anders geschrieben (Unit-Präfix): dann zählt die Anzahl der Parameter.
  Text := Source([
    'unit Demo;',
    'interface',
    'procedure Log(const AText: string); overload;',
    'procedure Log(const AText: string; ALevel: Integer); overload;',
    'implementation',
    'procedure Log(const AText: System.string; ALevel: Integer);',
    'begin',
    'end;',
    'procedure Log(const AText: System.string);',
    'begin',
    'end;',
    'end.']);
  Assert.AreEqual('8:10', Jump(Text, 2));
  Assert.AreEqual('5:10', Jump(Text, 3));
  Assert.AreEqual('3:10', Jump(Text, 6));
  Assert.AreEqual('2:10', Jump(Text, 9));
end;

procedure TAtlasMethodToggleTests.NestedAndGenericTypes;
var
  Text: string;
begin
  Text := Source([
    'unit Demo;',                                        // 0
    'interface',                                         // 1
    'type',                                              // 2
    '  TOuter = class',                                  // 3
    '  public type',                                     // 4
    '    TInner = class',                                // 5
    '      procedure Run;',                              // 6
    '    end;',                                          // 7
    '  public',                                          // 8
    '    procedure Run;',                                // 9
    '  end;',                                            // 10
    '  TBox<T: class, constructor> = class',             // 11
    '    function Get<U>(const AKey: U): T;',            // 12
    '  end;',                                            // 13
    'implementation',                                    // 14
    'procedure TOuter.TInner.Run;',                      // 15
    'begin',                                             // 16
    'end;',                                              // 17
    'procedure TOuter.Run;',                             // 18
    'begin',                                             // 19
    'end;',                                              // 20
    'function TBox<T>.Get<U>(const AKey: U): T;',        // 21
    'begin',                                             // 22
    '  Result := T.Create;',                             // 23
    'end;',                                              // 24
    'end.']);
  Assert.AreEqual('15:24', Jump(Text, 6, 8));
  Assert.AreEqual('18:17', Jump(Text, 9, 8));
  Assert.AreEqual('6:16', Jump(Text, 16));
  Assert.AreEqual('9:14', Jump(Text, 19));
  Assert.AreEqual('21:17', Jump(Text, 12, 6));
  Assert.AreEqual('12:13', Jump(Text, 23));
end;

procedure TAtlasMethodToggleTests.ClassMethodsConstructorsAndOperators;
var
  Text: string;
begin
  Text := Source([
    'unit Demo;',                                                      // 0
    'interface',                                                       // 1
    'type',                                                            // 2
    '  TPoint2 = record',                                              // 3
    '    X, Y: Integer;',                                              // 4
    '    class operator Add(const A, B: TPoint2): TPoint2;',           // 5
    '    class function Zero: TPoint2; static;',                       // 6
    '  end;',                                                          // 7
    '  TFoo = class',                                                  // 8
    '    constructor Create(AOwner: TObject);',                        // 9
    '    destructor Destroy; override;',                               // 10
    '  end;',                                                          // 11
    'implementation',                                                  // 12
    'class operator TPoint2.Add(const A, B: TPoint2): TPoint2;',       // 13
    'begin',                                                           // 14
    'end;',                                                            // 15
    'class function TPoint2.Zero: TPoint2;',                           // 16
    'begin',                                                           // 17
    'end;',                                                            // 18
    'constructor TFoo.Create(AOwner: TObject);',                       // 19
    'begin',                                                           // 20
    'end;',                                                            // 21
    'destructor TFoo.Destroy;',                                        // 22
    'begin',                                                           // 23
    '  inherited;',                                                    // 24
    'end;',                                                            // 25
    'end.']);
  Assert.AreEqual('13:23', Jump(Text, 5));
  Assert.AreEqual('16:23', Jump(Text, 6, 4));
  Assert.AreEqual('19:17', Jump(Text, 9));
  Assert.AreEqual('22:16', Jump(Text, 10));
  Assert.AreEqual('5:19', Jump(Text, 14));
  Assert.AreEqual('10:15', Jump(Text, 24));
end;

procedure TAtlasMethodToggleTests.StandaloneRoutinesInInterfaceAndForward;
var
  Text: string;
begin
  Text := Source([
    'unit Demo;',                              // 0
    'interface',                               // 1
    'function Twice(A: Integer): Integer;',    // 2
    'implementation',                          // 3
    'procedure Helper; forward;',              // 4
    'function Twice(A: Integer): Integer;',    // 5
    'begin',                                   // 6
    '  Helper;',                               // 7
    '  Result := 2 * A;',                      // 8
    'end;',                                    // 9
    'procedure Helper;',                       // 10
    'begin',                                   // 11
    'end;',                                    // 12
    'end.']);
  Assert.AreEqual('5:9', Jump(Text, 2));
  Assert.AreEqual('2:9', Jump(Text, 8));
  Assert.AreEqual('10:10', Jump(Text, 4));
  Assert.AreEqual('4:10', Jump(Text, 11));
end;

procedure TAtlasMethodToggleTests.LocalRoutinesBelongToOuterMethod;
var
  Text: string;
begin
  Text := Source([
    'unit Demo;',                          // 0
    'interface',                           // 1
    'type',                                // 2
    '  TFoo = class',                      // 3
    '    procedure Run;',                  // 4
    '    procedure Stop;',                 // 5
    '  end;',                              // 6
    'implementation',                      // 7
    'procedure TFoo.Run;',                 // 8
    'type',                                // 9
    '  TLocal = record A: Integer; end;',  // 10
    'var',                                 // 11
    '  Count: Integer;',                   // 12
    '  procedure Step;',                   // 13
    '  begin',                             // 14
    '    try',                             // 15
    '      Inc(Count);',                   // 16
    '    finally',                         // 17
    '    end;',                            // 18
    '  end;',                              // 19
    'begin',                               // 20
    '  case Count of',                     // 21
    '    0: Step;',                        // 22
    '  end;',                              // 23
    'end;',                                // 24
    'procedure TFoo.Stop;',                // 25
    'begin',                               // 26
    'end;',                                // 27
    'end.']);
  Assert.AreEqual('4:14', Jump(Text, 16));
  Assert.AreEqual('4:14', Jump(Text, 13));
  Assert.AreEqual('4:14', Jump(Text, 22));
  Assert.AreEqual('5:14', Jump(Text, 26));
  Assert.AreEqual('25:15', Jump(Text, 5));
end;

procedure TAtlasMethodToggleTests.ImplementationWithoutParameterList;
var
  Text: string;
begin
  // Delphi erlaubt im Implementierungskopf die Parameterliste wegzulassen.
  Text := Source([
    'unit Demo;',
    'interface',
    'type',
    '  TFoo = class',
    '    function Sum(A, B: Integer): Integer;',
    '  end;',
    'implementation',
    'function TFoo.Sum;',
    'begin',
    '  Result := A + B;',
    'end;',
    'end.']);
  Assert.AreEqual('7:14', Jump(Text, 4));
  Assert.AreEqual('4:13', Jump(Text, 9));
end;

procedure TAtlasMethodToggleTests.CommentsStringsAndDirectivesAreIgnored;
var
  Text: string;
begin
  Text := Source([
    'unit Demo;',                                          // 0
    'interface',                                           // 1
    'type',                                                // 2
    '  TFoo = class',                                      // 3
    '    // procedure Ghost;',                             // 4
    '    { procedure Ghost2; }',                           // 5
    '    procedure Run; {$IFDEF DEBUG} inline; {$ENDIF}',  // 6
    '  end;',                                              // 7
    'implementation',                                      // 8
    '(* procedure TFoo.Run; begin end; *)',                // 9
    'procedure TFoo.Run;',                                 // 10
    'begin',                                               // 11
    '  Writeln(''end; procedure TFoo.Ghost;'');',          // 12
    '  Writeln(''''''',                                    // 13
    '    end;',                                            // 14
    '    '''''');',                                        // 15
    'end;',                                                // 16
    'end.']);
  Assert.AreEqual('10:15', Jump(Text, 6));
  Assert.AreEqual('6:14', Jump(Text, 14));
  Assert.AreEqual('6:14', Jump(Text, 16));
  Assert.AreEqual('-', Jump(Text, 4));
  Assert.AreEqual('-', Jump(Text, 9));
end;

procedure TAtlasMethodToggleTests.RecordsInterfacesAndPropertiesDoNotConfuse;
var
  Text: string;
begin
  Text := Source([
    'unit Demo;',                                                       // 0
    'interface',                                                        // 1
    'type',                                                             // 2
    '  IRunner = interface',                                            // 3
    '    [''{6F0C8C4B-2D8B-4F0E-9A4E-5A5E3B0C1D2E}'']',                 // 4
    '    procedure Run;',                                               // 5
    '  end;',                                                           // 6
    '  TProc2 = procedure(A: Integer) of object;',                      // 7
    '  TVariant2 = record',                                             // 8
    '    case Kind: Byte of',                                           // 9
    '      0: (I: Integer; J: Integer);',                               // 10
    '      1: (R: record X: Integer; end);',                            // 11
    '  end;',                                                           // 12
    '  TFoo = class(TInterfacedObject, IRunner)',                       // 13
    '  private',                                                        // 14
    '    FItems: array of record Name: string; end;',                   // 15
    '    function GetItem(Index: Integer; const Key: string): string;', // 16
    '  public',                                                         // 17
    '    [Weak] FOwner: TObject;',                                      // 18
    '    property Items[Index: Integer; const Key: string]: string read GetItem; default;', // 19
    '    procedure Run;',                                               // 20
    '    procedure IRunner.Go = Run;',                                  // 21
    '  end;',                                                           // 22
    'implementation',                                                   // 23
    'function TFoo.GetItem(Index: Integer; const Key: string): string;',// 24
    'begin',                                                            // 25
    'end;',                                                             // 26
    'procedure TFoo.Run;',                                              // 27
    'begin',                                                            // 28
    'end;',                                                             // 29
    'end.']);
  Assert.AreEqual('24:14', Jump(Text, 16));
  Assert.AreEqual('27:15', Jump(Text, 20));
  Assert.AreEqual('20:14', Jump(Text, 28));
  Assert.AreEqual('16:13', Jump(Text, 25));
  // Interface-Methoden haben keine Implementierung unter ihrem Namen.
  Assert.AreEqual('-', Jump(Text, 5));
  Assert.AreEqual('-', Jump(Text, 21));
  Assert.AreEqual('-', Jump(Text, 19));
end;

procedure TAtlasMethodToggleTests.NoCounterpartOutsideOrForAbstract;
var
  Text: string;
begin
  Text := Source([
    'unit Demo;',
    'interface',
    'type',
    '  TBase = class',
    '    procedure Run; virtual; abstract;',
    '  end;',
    'function Lib: Integer; stdcall; external ''x.dll'';',
    'implementation',
    'procedure OnlyHere;',
    'begin',
    'end;',
    'end.']);
  Assert.AreEqual('-', Jump(Text, 4));
  Assert.AreEqual('-', Jump(Text, 6));
  Assert.AreEqual('-', Jump(Text, 9));
  Assert.AreEqual('-', Jump(Text, 0));
  Assert.AreEqual('-', Jump('', 0));
end;

procedure TAtlasMethodToggleTests.ProgramWithoutInterfaceSection;
var
  Text: string;
begin
  Text := Source([
    'program Demo;',                // 0
    'type',                         // 1
    '  TApp = class',               // 2
    '    procedure Run;',           // 3
    '  end;',                       // 4
    'procedure TApp.Run;',          // 5
    'begin',                        // 6
    'end;',                         // 7
    'begin',                        // 8
    '  TApp.Create.Run;',           // 9
    'end.']);
  Assert.AreEqual('5:15', Jump(Text, 3));
  Assert.AreEqual('3:14', Jump(Text, 6));
  Assert.AreEqual('-', Jump(Text, 9));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMethodToggleTests);

end.
