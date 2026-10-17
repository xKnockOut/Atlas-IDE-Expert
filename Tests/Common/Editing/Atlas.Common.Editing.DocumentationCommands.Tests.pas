unit Atlas.Common.Editing.DocumentationCommands.Tests;

// Tests für die Schnellbefehle /header, /deprecated, /region-all und /bookmark (#306).

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
    procedure BookmarkComment;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.SlashCommands;

/// <summary>Führt den Befehl in Zeile ALine aus und wendet die Änderungen an; '' wenn er nicht passt.</summary>
function Expand(const AText: string; ALine: Integer): string;
var
  Edits: TArray<TRuleEdit>;
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Offsets: TArray<Integer>;
  Index, Start, Stop: Integer;
begin
  if not TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, Edits) then
    Exit('');
  Lines := AText.Split([#10]);
  SetLength(Offsets, Length(Lines) + 1);
  Offsets[0] := 0;
  for Index := 0 to High(Lines) do
    Offsets[Index + 1] := Offsets[Index] + Length(Lines[Index]) + 1;
  TArray.Sort<TRuleEdit>(Edits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for Edit in Edits do
  begin
    Start := Offsets[Edit.Range.StartPos.Line] + Edit.Range.StartPos.Character;
    Stop := Offsets[Edit.Range.EndPos.Line] + Edit.Range.EndPos.Character;
    Result := Copy(Result, 1, Start) + Edit.NewText + Copy(Result, Stop + 1, MaxInt);
  end;
end;

procedure TDocumentationCommandsTests.HeaderOnlyOnce;
var
  Once, Twice: string;
begin
  Once := Expand('unit U;'#10'/header'#10'interface'#10'implementation'#10'end.', 1);
  Assert.StartsWith('{ U'#10'  Copyright (c) ' + IntToStr(CurrentYear), Once);
  Assert.EndsWith('}'#10'unit U;'#10'interface'#10'implementation'#10'end.', Once);
  // Zweiter Aufruf: Der Kopf ist aktuell, nur die Befehlszeile verschwindet.
  Twice := Expand(StringReplace(Once, 'unit U;'#10, 'unit U;'#10'/header'#10, []), 3);
  Assert.AreEqual(Once, Twice);
end;

procedure TDocumentationCommandsTests.HeaderUpdatesYear;
begin
  Assert.AreEqual('{ Copyright 2019-' + IntToStr(CurrentYear) + ' Firma }'#10'unit U;'#10'interface'#10 +
    'implementation'#10'end.', Expand('{ Copyright 2019 Firma }'#10'unit U;'#10'/header'#10'interface'#10 +
    'implementation'#10'end.', 2));
  Assert.AreEqual('// (c) 2010-' + IntToStr(CurrentYear) + #10'unit U;'#10'interface'#10'implementation'#10'end.',
    Expand('// (c) 2010-2020'#10'unit U;'#10'/header'#10'interface'#10'implementation'#10'end.', 2));
end;

procedure TDocumentationCommandsTests.HeaderWrongPlace;
const
  Include = '/header'#10'procedure P;'#10'begin'#10'end;'#10;
var
  Problems: TArray<TSlashProblem>;
begin
  // Include-Datei ohne unit: kein Kopf, die Befehlszeile bleibt mit Hinweis stehen.
  Assert.AreEqual('', Expand(Include, 0));
  Problems := TSlashCommandRegistry.Shared.Problems(Include, nil);
  Assert.AreEqual(1, Integer(Length(Problems)));
  Assert.AreEqual('/header gilt nur in einer Unit', Problems[0].Message);
end;

procedure TDocumentationCommandsTests.DeprecatedAtMethodDeclaration;
const
  Source =
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
    'end.', Expand(Source, 8));
end;

procedure TDocumentationCommandsTests.DeprecatedType;
const
  Source =
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
    'end.', Expand(Source, 3));
end;

procedure TDocumentationCommandsTests.DeprecatedWrongPlace;
begin
  // Über einer Anweisung statt einer Deklaration.
  Assert.AreEqual('', Expand('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  /deprecated Alt'#10'  Run;'#10'end;'#10'end.', 5));
  // Schon markiert.
  Assert.AreEqual('', Expand('unit U;'#10'interface'#10'/deprecated'#10'procedure P; deprecated;'#10 +
    'implementation'#10'end.', 2));
end;

procedure TDocumentationCommandsTests.RegionAllGroupsMethods;
const
  Source =
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
  Result_: string;
begin
  Result_ := Expand(Source, 9);
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
    'end.', Copy(Result_, Pos('implementation', Result_), MaxInt));
  Assert.AreEqual(0, Pos('/region-all', Result_));
end;

procedure TDocumentationCommandsTests.RegionAllOutsideClassFails;
begin
  Assert.AreEqual('', Expand('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  /region-all'#10'end;'#10'end.', 5));
end;

procedure TDocumentationCommandsTests.BookmarkComment;
begin
  Assert.AreEqual('unit U;'#10'implementation'#10'procedure P;'#10'begin'#10'  // @bookmark Abrechnung'#10 +
    'end;'#10'end.', Expand('unit U;'#10'implementation'#10'procedure P;'#10'begin'#10'  /bookmark Abrechnung'#10 +
    'end;'#10'end.', 4));
  Assert.AreEqual('', Expand('unit U;'#10'implementation'#10'procedure P;'#10'begin'#10'  /bookmark'#10 +
    'end;'#10'end.', 4));
end;

initialization
  TDUnitX.RegisterTestFixture(TDocumentationCommandsTests);

end.
