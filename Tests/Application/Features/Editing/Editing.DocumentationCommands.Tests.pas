unit Editing.DocumentationCommands.Tests;

// Tests für die Schnellbefehle /header, /deprecated, /region-all (#306); /bookmark ist gestrichen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDocumentationCommandsTests = class
  public
    [Test]
    procedure HeaderOnlyOnce;
    [Test]
    procedure HeaderUpdatesYear;
    [Test]
    procedure HeaderWrongPlace;
    [Test]
    procedure DeprecatedAtMethodDeclaration;
    [Test]
    procedure DeprecatedType;
    [Test]
    procedure DeprecatedWrongPlace;
    [Test]
    procedure RegionAllGroupsMethods;
    [Test]
    procedure RegionAllOutsideClassFails;
    [Test]
    procedure BookmarkIsGone;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Editing.SlashCommands,
  Editing.Contract,
  Editing.SlashCommands.TestSupport;

{ TDocumentationCommandsTests }

procedure TDocumentationCommandsTests.HeaderOnlyOnce;
var
  mOnce, mTwice: string;
begin
  mOnce := TSlashTest.ExpandOrEmpty('unit U;'#10'/header'#10'interface'#10'implementation'#10'end.', 1);
  Assert.StartsWith('{ U'#10'  Copyright (c) ' + IntToStr(CurrentYear), mOnce);
  Assert.EndsWith('}'#10'unit U;'#10'interface'#10'implementation'#10'end.', mOnce);
  // Zweiter Aufruf: Der Kopf ist aktuell, nur die Befehlszeile verschwindet.
  mTwice := TSlashTest.ExpandOrEmpty(StringReplace(mOnce, 'unit U;'#10, 'unit U;'#10'/header'#10, []), 3);
  Assert.AreEqual(mOnce, mTwice);
end;

procedure TDocumentationCommandsTests.HeaderUpdatesYear;
begin
  Assert.AreEqual('{ Copyright 2019-' + IntToStr(CurrentYear) + ' Firma }'#10'unit U;'#10'interface'#10 +
    'implementation'#10'end.', TSlashTest.ExpandOrEmpty('{ Copyright 2019 Firma }'#10'unit U;'#10'/header'#10'interface'#10 +
    'implementation'#10'end.', 2));
  Assert.AreEqual('// (c) 2010-' + IntToStr(CurrentYear) + #10'unit U;'#10'interface'#10'implementation'#10'end.',
    TSlashTest.ExpandOrEmpty('// (c) 2010-2020'#10'unit U;'#10'/header'#10'interface'#10'implementation'#10'end.', 2));
end;

procedure TDocumentationCommandsTests.HeaderWrongPlace;
const
  cInclude = '/header'#10'procedure P;'#10'begin'#10'end;'#10;
var
  mProblems: TArray<TSlashProblem>;
begin
  // Include-Datei ohne unit: kein Kopf, die Befehlszeile bleibt mit Hinweis stehen.
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty(cInclude, 0));
  mProblems := TSlashCommandRegistry.Shared.Problems(cInclude, nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual('/header gilt nur in einer Unit', mProblems[0].Message);
end;

procedure TDocumentationCommandsTests.DeprecatedAtMethodDeclaration;
const
  cSource =
    'unit U;'#10 +                      // 0
    'interface'#10 +                    // 1
    'type'#10 +                         // 2
    '  TFoo = class'#10 +               // 3
    '  public'#10 +                     // 4
    '    procedure Foo; overload;'#10 + // 5
    '  end;'#10 +                       // 6
    'implementation'#10 +               // 7
    '/deprecated Bar nutzen'#10 +       // 8
    'procedure TFoo.Foo;'#10 +          // 9
    'begin'#10 +                        // 10
    'end;'#10 +                         // 11
    'end.';
begin
  Assert.AreEqual(
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  public'#10 +
    '    /// <remarks>Veraltet: Bar nutzen</remarks>'#10 +
    '    procedure Foo; overload; deprecated ''Bar nutzen'';'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Foo;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.', TSlashTest.ExpandOrEmpty(cSource, 8));
end;

procedure TDocumentationCommandsTests.DeprecatedType;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  /deprecated'#10 +
    '  TAlt = record'#10 +
    '    A: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
begin
  Assert.AreEqual(
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  /// <remarks>Veraltet</remarks>'#10 +
    '  TAlt = record'#10 +
    '    A: Integer;'#10 +
    '  end deprecated;'#10 +
    'implementation'#10 +
    'end.', TSlashTest.ExpandOrEmpty(cSource, 3));
end;

procedure TDocumentationCommandsTests.DeprecatedWrongPlace;
begin
  // Über einer Anweisung statt einer Deklaration.
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  /deprecated Alt'#10'  Run;'#10'end;'#10'end.', 5));
  // Schon markiert.
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty('unit U;'#10'interface'#10'/deprecated'#10'procedure P; deprecated;'#10 +
    'implementation'#10'end.', 2));
end;

procedure TDocumentationCommandsTests.RegionAllGroupsMethods;
const
  cSource =
    'unit U;'#10 +                                       // 0
    'interface'#10 +                                     // 1
    'type'#10 +                                          // 2
    '  TForm1 = class(TForm)'#10 +                       // 3
    '    procedure Button1Click(Sender: TObject);'#10 +  // 4
    '  private'#10 +                                     // 5
    '    function GetName: string;'#10 +                 // 6
    '    procedure Laden;'#10 +                          // 7
    '  public'#10 +                                      // 8
    '    /region-all'#10 +                               // 9
    '    constructor Create;'#10 +                       // 10
    '  end;'#10 +                                        // 11
    'implementation'#10 +                                // 12
    'procedure TForm1.Laden;'#10 +                       // 13
    'begin'#10 +                                         // 14
    'end;'#10 +                                          // 15
    ''#10 +                                              // 16
    '// Name aus der Datenbank'#10 +                     // 17
    'function TForm1.GetName: string;'#10 +              // 18
    'begin'#10 +                                         // 19
    'end;'#10 +                                          // 20
    ''#10 +                                              // 21
    'constructor TForm1.Create;'#10 +                    // 22
    'begin'#10 +                                         // 23
    'end;'#10 +                                          // 24
    ''#10 +                                              // 25
    'procedure TForm1.Button1Click(Sender: TObject);'#10 + // 26
    'begin'#10 +                                         // 27
    'end;'#10 +                                          // 28
    ''#10 +                                              // 29
    'end.';
var
  mResult_: string;
begin
  mResult_ := TSlashTest.ExpandOrEmpty(cSource, 9);
  Assert.AreEqual(
    'implementation'#10 +
    '{$REGION ''Ereignis-Handler''}'#10 +
    'procedure TForm1.Button1Click(Sender: TObject);'#10'begin'#10'end;'#10 +
    '{$ENDREGION}'#10 +
    #10 +
    '{$REGION ''Public''}'#10 +
    'constructor TForm1.Create;'#10'begin'#10'end;'#10 +
    '{$ENDREGION}'#10 +
    #10 +
    '{$REGION ''Private''}'#10 +
    'procedure TForm1.Laden;'#10'begin'#10'end;'#10 +
    '{$ENDREGION}'#10 +
    #10 +
    '{$REGION ''Getter und Setter''}'#10 +
    '// Name aus der Datenbank'#10 +
    'function TForm1.GetName: string;'#10'begin'#10'end;'#10 +
    '{$ENDREGION}'#10 +
    #10 +
    'end.', Copy(mResult_, Pos('implementation', mResult_), MaxInt));
  Assert.AreEqual(0, Pos('/region-all', mResult_));
end;

procedure TDocumentationCommandsTests.RegionAllOutsideClassFails;
begin
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  /region-all'#10'end;'#10'end.', 5));
end;

procedure TDocumentationCommandsTests.BookmarkIsGone;
begin
  // #306: /bookmark ist laut Ergänzung gestrichen; die Zeile bleibt als unbekannter Befehl.
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty('unit U;'#10'implementation'#10'procedure P;'#10'begin'#10'  /bookmark Abrechnung'#10 +
    'end;'#10'end.', 4));
end;

initialization
  TDUnitX.RegisterTestFixture(TDocumentationCommandsTests);

end.
