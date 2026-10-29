unit Atlas.Common.Lsp.CompilerFixes.Tests;

// Tests für die Code-Aktionen an Compilermeldungen, Teil 2 (#549).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspCompilerFixesTests = class
  public
    [Test]
    procedure OffersFixAndFixAll;
    [Test]
    procedure OnlyLinesOfRange;
    [Test]
    procedure DisabledOffersNothing;
    /// <summary>Steht der Cursor auf dem Bezeichner, bietet schon die uses-Aktion (#284) die Unit an.</summary>
    [Test]
    procedure E2003NotTwiceOnIdentifier;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CompilerFixes,
  Atlas.Common.Lsp.CompilerFixes;

const
  Uri = 'file:///C:/Projekt/A.pas';
  Source =
    'unit A;' + #10 +                              // 0
    'interface' + #10 +                            // 1
    'implementation' + #10 +                       // 2
    'procedure P(const A: AnsiString);' + #10 +    // 3
    'var' + #10 +                                  // 4
    '  S, T: string;' + #10 +                      // 5
    '  L: TStringList;' + #10 +                    // 6
    'begin' + #10 +                                // 7
    '  S := A;' + #10 +                            // 8
    '  T := A;' + #10 +                            // 9
    '  Zeige(S + T);' + #10 +                      // 10
    'end;' + #10 +
    'end.';

function Msg(ALine: Integer; const ACode, AText: string): TCompilerMessage;
begin
  Result := Default(TCompilerMessage);
  Result.FileName := 'C:\Projekt\A.pas';
  Result.Line := ALine;
  Result.Column := -1;
  Result.Code := ACode;
  Result.Text := AText;
end;

function Context: TCompilerFixContext;
begin
  Result := Default(TCompilerFixContext);
  Result.Declaring :=
    function(const AName: string): TArray<string>
    begin
      Result := nil;
      if SameText(AName, 'TStringList') then
        Result := TArray<string>.Create('System.Classes');
    end;
end;

function Titles(AEnabled: Boolean; const ARange: TTextRange): string;
var
  Tree: TSyntaxTree;
  Actions: TArray<TJSONObject>;
  Action: TJSONObject;
begin
  Result := '';
  Tree := TPascalParser.Parse(Source);
  try
    Actions := TLspCompilerFixes.Actions(AEnabled, Source, Tree, Uri, ARange,
      [Msg(8, 'W1057', 'x ''AnsiString'' y ''string'''), Msg(8, 'W1057', 'x ''AnsiString'' y ''string'''),
      Msg(9, 'W1057', 'x ''AnsiString'' y ''string'''), Msg(6, 'E2003', 'Undeclared identifier: ''TStringList'''),
      Msg(-1, 'W1057', 'ohne Zeile')], Context);
    for Action in Actions do
    begin
      Result := Result + Action.GetValue<string>('title', '') + ' [' + Action.GetValue<string>('kind', '') + ']|';
      Action.Free;
    end;
  finally
    Tree.Free;
  end;
end;

procedure TLspCompilerFixesTests.OffersFixAndFixAll;
begin
  Assert.AreEqual('Explizit umwandeln: string(…) (W1057) [quickfix]|' +
    'Alle W1057 in der Datei beheben (2) [quickfix]|', Titles(True, TTextRange.Create(8, 2, 8, 2)));
end;

procedure TLspCompilerFixesTests.OnlyLinesOfRange;
begin
  Assert.AreEqual('', Titles(True, TTextRange.Create(10, 0, 10, 0)));
  Assert.AreEqual('uses System.Classes ergänzen (E2003: TStringList) [quickfix]|',
    Titles(True, TTextRange.Create(6, 0, 6, 0)));
end;

procedure TLspCompilerFixesTests.DisabledOffersNothing;
begin
  Assert.AreEqual('', Titles(False, TTextRange.Create(8, 0, 9, 0)));
end;

procedure TLspCompilerFixesTests.E2003NotTwiceOnIdentifier;
begin
  Assert.AreEqual('', Titles(True, TTextRange.Create(6, 6, 6, 6)));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCompilerFixesTests);

end.
