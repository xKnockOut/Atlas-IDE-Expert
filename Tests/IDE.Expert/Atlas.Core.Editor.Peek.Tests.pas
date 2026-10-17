unit Atlas.Core.Editor.Peek.Tests;

// Tests für Definition und Referenzen einblenden (#505).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasPeekTests = class
  public
    [Test]
    procedure RoutineDeclarationEndsAtSemicolonAndDirectives;
    [Test]
    procedure TypeBlockEndsAtMatchingEnd;
    [Test]
    procedure ForwardClassIsOneLine;
    [Test]
    procedure StartIncludesDocCommentsAndAttributes;
    [Test]
    procedure BodyEndSkipsLocalRoutinesAndNestedBlocks;
    [Test]
    procedure ExternalHasNoBody;
    [Test]
    procedure CommentsAndStringsDoNotCount;
    [Test]
    procedure PairsOverloadsWithImplementations;
    [Test]
    procedure FindsOverloadsInOutline;
    [Test]
    procedure BodyOutsideTheListIsTaken;
    [Test]
    procedure DefinitionRowsShowDeclarationAndBody;
    [Test]
    procedure ReferenceRowsMarkTheName;
    [Test]
    procedure ViewSelectsAndScrolls;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Editor.Peek;

const
  UnitText: array[0..41] of string = (
    'unit U;',                                           // 0
    'interface',                                         // 1
    'type',                                              // 2
    '  TFoo = class;',                                   // 3
    '  /// <summary>Doku</summary>',                     // 4
    '  [Serializable]',                                  // 5
    '  TBar = class(TObject)',                           // 6
    '  private',                                         // 7
    '    FData: record A, B: Integer; end;',             // 8
    '  public',                                          // 9
    '    procedure Add(A: Integer); overload;',          // 10
    '    procedure Add(const S: string;',                // 11
    '      B: Integer); overload; virtual;',             // 12
    '    procedure Add; overload;',                      // 13
    '    class function Make: TBar;',                    // 14
    '  end;',                                            // 15
    '  TFoo = class',                                    // 16
    '  end;',                                            // 17
    'implementation',                                    // 18
    'procedure TBar.Add(A: Integer);',                   // 19
    '  procedure Inner;',                                // 20
    '  begin',                                           // 21
    '  end;',                                            // 22
    'var',                                               // 23
    '  X: Integer;',                                     // 24
    'begin',                                             // 25
    '  try',                                             // 26
    '    case A of 1: X := 1; end; { end }',             // 27
    '  finally',                                         // 28
    '    Log(''end;'');',                                // 29
    '  end;',                                            // 30
    'end;',                                              // 31
    'procedure TBar.Add(const S: string; B: Integer);',  // 32
    'begin',                                             // 33
    'end;',                                              // 34
    'procedure TBar.Add;',                               // 35
    'begin',                                             // 36
    'end;',                                              // 37
    'procedure Ext; external ''x.dll'';',                // 38
    'class function TBar.Make: TBar;',                   // 39
    'begin end;',                                        // 40
    'end.');                                             // 41

function Lines: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(UnitText));
  for Index := 0 to High(UnitText) do
    Result[Index] := UnitText[Index];
end;

function At(ALine, ACharacter: Integer): TAtlasPeekPlace;
begin
  Result := TAtlasPeekPlace.Create('U.pas', ALine, ACharacter);
end;

procedure TAtlasPeekTests.RoutineDeclarationEndsAtSemicolonAndDirectives;
begin
  Assert.AreEqual(10, TAtlasPeek.DeclarationEnd(Lines, 10));
  // Parameter über zwei Zeilen: das ";" in der Klammer zählt nicht.
  Assert.AreEqual(12, TAtlasPeek.DeclarationEnd(Lines, 11));
  Assert.AreEqual(14, TAtlasPeek.DeclarationEnd(Lines, 14));
  Assert.AreEqual(24, TAtlasPeek.DeclarationEnd(Lines, 24));
  // Direktiven in der Folgezeile gehören dazu.
  Assert.AreEqual(1, TAtlasPeek.DeclarationEnd(['procedure A;', '  overload;', 'procedure B;'], 0));
end;

procedure TAtlasPeekTests.TypeBlockEndsAtMatchingEnd;
begin
  // Das record im Feld hat ein eigenes end.
  Assert.AreEqual(15, TAtlasPeek.DeclarationEnd(Lines, 6));
  Assert.AreEqual(17, TAtlasPeek.DeclarationEnd(Lines, 16));
  Assert.AreEqual(3, TAtlasPeek.DeclarationEnd(['type', '  TR = packed record', '    A: Integer;', '  end;', 'X'], 1));
  Assert.AreEqual(2, TAtlasPeek.DeclarationEnd(['  IFoo = interface', '    [''{0}'']', '  end;'], 0));
end;

procedure TAtlasPeekTests.ForwardClassIsOneLine;
begin
  Assert.AreEqual(3, TAtlasPeek.DeclarationEnd(Lines, 3));
  Assert.AreEqual(0, TAtlasPeek.DeclarationEnd(['  TC = class of TBar;', 'X'], 0));
  Assert.AreEqual(0, TAtlasPeek.DeclarationEnd(['  E = class(Exception);', 'X'], 0));
end;

procedure TAtlasPeekTests.StartIncludesDocCommentsAndAttributes;
begin
  Assert.AreEqual(4, TAtlasPeek.DeclarationStart(Lines, 6));
  Assert.AreEqual(10, TAtlasPeek.DeclarationStart(Lines, 10));
  Assert.AreEqual(0, TAtlasPeek.DeclarationStart(Lines, 0));
end;

procedure TAtlasPeekTests.BodyEndSkipsLocalRoutinesAndNestedBlocks;
begin
  Assert.AreEqual(31, TAtlasPeek.BodyEnd(Lines, 19));
  Assert.AreEqual(34, TAtlasPeek.BodyEnd(Lines, 32));
  Assert.AreEqual(40, TAtlasPeek.BodyEnd(Lines, 39));
end;

procedure TAtlasPeekTests.ExternalHasNoBody;
begin
  Assert.AreEqual(38, TAtlasPeek.BodyEnd(Lines, 38));
end;

procedure TAtlasPeekTests.CommentsAndStringsDoNotCount;
begin
  Assert.AreEqual(3, TAtlasPeek.BodyEnd(['procedure P;', 'begin', '  { begin } (* end; *) S := ''end;'' // end;',
    'end;', 'X'], 0));
  Assert.AreEqual(4, TAtlasPeek.BodyEnd(['procedure P;', 'begin', '  {', '  end; }', 'end;'], 0));
end;

procedure TAtlasPeekTests.PairsOverloadsWithImplementations;
var
  Targets: TArray<TAtlasPeekTarget>;
begin
  // Drei Überladungen samt Implementierungen; "Gehe zu Definition" führt von 10 → 19, 11 → 32, 13 → 35.
  Targets := TAtlasPeek.Pair([At(10, 14), At(11, 14), At(13, 14), At(19, 15), At(32, 15), At(35, 15)],
    function(const APlace: TAtlasPeekPlace; out ATarget: TAtlasPeekPlace): Boolean
    begin
      Result := True;
      case APlace.Line of
        10: ATarget := At(19, 15);
        11: ATarget := At(32, 15);
        13: ATarget := At(35, 15);
      else
        Result := False;
      end;
    end);
  Assert.AreEqual(3, Integer(Length(Targets)));
  Assert.AreEqual(10, Targets[0].Place.Line);
  Assert.IsTrue(Targets[0].HasBody);
  Assert.AreEqual(19, Targets[0].Body.Line);
  Assert.AreEqual(32, Targets[1].Body.Line);
  Assert.AreEqual(35, Targets[2].Body.Line);
  // Ohne Ziel (abstrakt): eigenes Ziel ohne Implementierung.
  Targets := TAtlasPeek.Pair([At(14, 19)], nil);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.IsFalse(Targets[0].HasBody);
end;

function Symbol(const AName, AContainer: string; AKind, ALine: Integer): TAtlasSymbol;
begin
  Result.Name := AName;
  Result.Container := AContainer;
  Result.Kind := AKind;
  Result.FileName := 'U.pas';
  Result.Line := ALine;
  Result.Character := 4;
end;

procedure TAtlasPeekTests.FindsOverloadsInOutline;
var
  Symbols: TArray<TAtlasSymbol>;
  Places: TArray<TAtlasPeekPlace>;
begin
  Symbols := [Symbol('TBar', 'interface', 5, 6), Symbol('Add', 'TBar', 6, 10), Symbol('Add', 'TBar', 6, 11),
    Symbol('Add', 'TBar', 6, 13), Symbol('Make', 'TBar', 12, 14), Symbol('Add', 'TOther', 6, 16),
    Symbol('TBar.Add', 'implementation', 6, 32), Symbol('TBar.Add', 'implementation', 6, 19),
    Symbol('TBar.Add', 'implementation', 6, 35), Symbol('Add', 'interface', 12, 3)];
  Places := TAtlasPeek.Overloads(Symbols, 11);
  // Drei Deklarationen und drei Implementierungen, nach Zeile; TOther.Add und die freie Funktion nicht.
  Assert.AreEqual(6, Integer(Length(Places)));
  Assert.AreEqual(10, Places[0].Line);
  Assert.AreEqual(11, Places[1].Line);
  Assert.AreEqual(13, Places[2].Line);
  Assert.AreEqual(19, Places[3].Line);
  Assert.AreEqual(32, Places[4].Line);
  Assert.AreEqual(35, Places[5].Line);
  // Freie Routine: interface und implementation sind derselbe Besitzer.
  Symbols := Symbols + [Symbol('Add', 'implementation', 12, 50)];
  Places := TAtlasPeek.Overloads(Symbols, 3);
  Assert.AreEqual(2, Integer(Length(Places)));
  Assert.AreEqual(50, Places[1].Line);
  // Kein Routinenname in der Zeile (Klasse): leer.
  Assert.AreEqual(0, Integer(Length(TAtlasPeek.Overloads(Symbols, 6))));
end;

procedure TAtlasPeekTests.BodyOutsideTheListIsTaken;
var
  Targets: TArray<TAtlasPeekTarget>;
begin
  Targets := TAtlasPeek.Pair([At(10, 14)],
    function(const APlace: TAtlasPeekPlace; out ATarget: TAtlasPeekPlace): Boolean
    begin
      ATarget := TAtlasPeekPlace.Create('V.pas', 70, 2);
      Result := True;
    end);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.IsTrue(Targets[0].HasBody);
  Assert.AreEqual('V.pas', Targets[0].Body.FileName);
  // Implementierung, die zurück zu einer schon vergebenen Deklaration führt: kein Rumpf.
  Targets := TAtlasPeek.Pair([At(10, 14), At(19, 15), At(40, 1)],
    function(const APlace: TAtlasPeekPlace; out ATarget: TAtlasPeekPlace): Boolean
    begin
      Result := True;
      case APlace.Line of
        10: ATarget := At(19, 15);
      else
        ATarget := At(10, 14);
      end;
    end);
  Assert.AreEqual(2, Integer(Length(Targets)));
  Assert.AreEqual(40, Targets[1].Place.Line);
  Assert.IsFalse(Targets[1].HasBody);
end;

procedure TAtlasPeekTests.DefinitionRowsShowDeclarationAndBody;
var
  Target: TAtlasPeekTarget;
  Rows: TArray<TAtlasPeekRow>;
begin
  Target.Place := At(11, 14);
  Target.HasBody := True;
  Target.Body := At(32, 15);
  Rows := TAtlasPeek.DefinitionRows(Target, Lines, Lines, True, 4);
  // Zwei Zeilen Deklaration, Trennzeile, drei Zeilen Implementierung.
  Assert.AreEqual(6, Integer(Length(Rows)));
  Assert.IsTrue(Rows[0].Target);
  Assert.AreEqual('Add', Copy(Rows[0].Text, Rows[0].NameStart + 1, Rows[0].NameStop - Rows[0].NameStart));
  Assert.IsFalse(Rows[1].Target);
  Assert.AreEqual(Ord(TAtlasPeekRowKind.Separator), Ord(Rows[2].Kind));
  Assert.AreEqual(32, Rows[2].Line);
  Assert.AreEqual(32, Rows[3].Line);
  Assert.AreEqual(34, Rows[5].Line);
  // Implementierung abgeschaltet: nur die Deklaration.
  Rows := TAtlasPeek.DefinitionRows(Target, Lines, Lines, False, 4);
  Assert.AreEqual(2, Integer(Length(Rows)));
end;

procedure TAtlasPeekTests.ReferenceRowsMarkTheName;
var
  Rows: TArray<TAtlasPeekRow>;
  Source: TArray<string>;
  Index: Integer;
begin
  SetLength(Source, 100);
  for Index := 0 to High(Source) do
    Source[Index] := Format('L%d', [Index]);
  Source[50] := #9'Foo(1);';
  Rows := TAtlasPeek.ReferenceRows(At(50, 1), Source, 4);
  Assert.AreEqual(TAtlasPeek.ReferenceBefore + TAtlasPeek.ReferenceAfter + 1, Integer(Length(Rows)));
  Assert.AreEqual(47, Rows[0].Line);
  Assert.IsTrue(Rows[3].Target);
  Assert.AreEqual('    Foo(1);', Rows[3].Text);
  Assert.AreEqual(4, Rows[3].NameStart);
  Assert.AreEqual(7, Rows[3].NameStop);
  // Am Dateianfang und -ende abgeschnitten.
  Rows := TAtlasPeek.ReferenceRows(At(0, 0), Source, 4);
  Assert.AreEqual(0, Rows[0].Line);
  Rows := TAtlasPeek.ReferenceRows(At(99, 0), Source, 4);
  Assert.AreEqual(99, Rows[High(Rows)].Line);
  Assert.AreEqual('L1', TAtlasPeek.Excerpt(#9' L1  '));
end;

procedure TAtlasPeekTests.ViewSelectsAndScrolls;
var
  View: TAtlasPeekView;
  Entries: TArray<TAtlasPeekEntry>;
  Source: TArray<string>;
  Index: Integer;
begin
  SetLength(Source, 100);
  for Index := 0 to High(Source) do
    Source[Index] := Format('L%d', [Index]);
  SetLength(Entries, 2);
  Entries[0].Target.Place := At(10, 0);
  Entries[0].Rows := TAtlasPeek.ReferenceRows(At(10, 0), Source, 4);
  Entries[1].Target.Place := At(60, 0);
  Entries[1].Rows := TAtlasPeek.ReferenceRows(At(60, 0), Source, 4);
  View := TAtlasPeekView.Create(TAtlasPeekMode.References, 'Foo', Entries);
  try
    View.PageRows := 15;
    Assert.AreEqual(0, View.Top);
    View.PageDown;
    Assert.AreEqual(14, View.Top);
    View.PageDown;
    View.PageDown;
    Assert.AreEqual(View.MaxTop, View.Top);
    Assert.AreEqual(44 - 15, View.MaxTop);
    // Zielzeile außer Sicht: Enter öffnet die oberste sichtbare Zeile.
    Assert.AreEqual(7 + View.Top, View.OpenPlace.Line);
    View.PageUp;
    View.PageUp;
    View.PageUp;
    Assert.AreEqual(0, View.Top);
    Assert.AreEqual(10, View.OpenPlace.Line);
    View.SelectNext;
    Assert.AreEqual(1, View.Selected);
    View.SelectNext;
    Assert.AreEqual(1, View.Selected);
    Assert.AreEqual(60, View.OpenPlace.Line);
    View.SelectPrevious;
    View.SelectPrevious;
    Assert.AreEqual(0, View.Selected);
  finally
    View.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPeekTests);

end.
