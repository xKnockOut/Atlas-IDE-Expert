unit Atlas.Common.Lsp.StringLiteralCommands.Tests;

// Tests für atlas.server.plainText und atlas.server.textToLiteral (#312,
// #415): Klartext eines verketteten Literals, Fehler ohne Literal, Literal
// mit der Einrückung der Zeile und dem Zeilenende des Dokuments, mehrzeiliger
// String, ungültige Argumente.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TStringLiteralCommandsTests = class
  public
    [Test]
    procedure PlainTextOfConcatenatedLiteral;
    [Test]
    procedure PlainTextWithoutLiteralRaises;
    [Test]
    procedure ToLiteralUsesIndentOfLine;
    [Test]
    procedure ToLiteralUsesLineBreakOfDocument;
    [Test]
    procedure ToLiteralMultiline;
    [Test]
    procedure RejectsBadArguments;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Common.Lsp.StringLiteralCommands;

const
  cMainFile = 'C:\P\Haupt.pas';
  cUnitLf =
    'unit Haupt;'#10 +
    'implementation'#10 +
    'procedure Lauf;'#10 +
    'begin'#10 +
    '    S := ''select *'' + sLineBreak + ''from Kunde'';'#10 +
    '    X := 1;'#10 +
    'end;'#10 +
    'end.';

function StoreWith(const AText: string): IDocumentStore;
begin
  Result := TDocumentStore.Create;
  Result.Open(TDocumentUris.FromPath(cMainFile), 'delphi', 1, AText);
end;

/// <summary>Argumente URI, Position und, wenn AText nicht leer ist, der Text.</summary>
function Arguments(ALine, ACharacter: Integer; const AText: string): TJSONArray;
var
  mPosition: TJSONObject;
begin
  Result := TJSONArray.Create;
  Result.Add(TDocumentUris.FromPath(cMainFile));
  mPosition := TJSONObject.Create;
  mPosition.AddPair('line', TJSONNumber.Create(ALine));
  mPosition.AddPair('character', TJSONNumber.Create(ACharacter));
  Result.AddElement(mPosition);
  if AText <> '' then
  begin
    Result.Add(AText);
  end;
end;

function ToLiteral(const AStore: IDocumentStore; ALine: Integer; const AText: string; AMultiline: Boolean): string;
var
  mArgs: TJSONArray;
  mAnswer: TJSONValue;
  mSettings: TStringLiteralSettings;
begin
  mSettings := TStringLiteralSettings.Default;
  mSettings.LineBreak := TStringLiteralBreak.SLineBreak;
  mSettings.MaxLineLength := 0;
  mArgs := Arguments(ALine, 0, AText);
  try
    mAnswer := TStringLiteralCommands.ExecuteToLiteral(AStore, mSettings, AMultiline, mArgs);
    try
      Result := mAnswer.Value;
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
  end;
end;

{ TStringLiteralCommandsTests }

procedure TStringLiteralCommandsTests.PlainTextOfConcatenatedLiteral;
var
  mArgs: TJSONArray;
  mAnswer: TJSONValue;
begin
  mArgs := Arguments(4, 12, '');
  try
    mAnswer := TStringLiteralCommands.ExecutePlainText(StoreWith(cUnitLf), mArgs);
    try
      Assert.IsTrue(mAnswer is TJSONString);
      Assert.AreEqual('select *'#13#10'from Kunde', mAnswer.Value);
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
  end;
end;

procedure TStringLiteralCommandsTests.PlainTextWithoutLiteralRaises;
begin
  Assert.WillRaise(
    procedure
    var
      Args: TJSONArray;
    begin
      Args := Arguments(5, 6, '');
      try
        TStringLiteralCommands.ExecutePlainText(StoreWith(cUnitLf), Args).Free;
      finally
        Args.Free;
      end;
    end, EJsonRpcError);
end;

procedure TStringLiteralCommandsTests.ToLiteralUsesIndentOfLine;
begin
  Assert.AreEqual('''select *'' + sLineBreak +'#10'    ''from Kunde''',
    ToLiteral(StoreWith(cUnitLf), 5, 'select *'#10'from Kunde', False));
  // Zeile ohne Einzug.
  Assert.AreEqual('''a'' + sLineBreak +'#10'''b''', ToLiteral(StoreWith(cUnitLf), 0, 'a'#10'b', False));
end;

procedure TStringLiteralCommandsTests.ToLiteralUsesLineBreakOfDocument;
begin
  Assert.AreEqual('''select *'' + sLineBreak +'#13#10'    ''from Kunde''',
    ToLiteral(StoreWith(StringReplace(cUnitLf, #10, #13#10, [rfReplaceAll])), 5, 'select *'#10'from Kunde', False));
end;

procedure TStringLiteralCommandsTests.ToLiteralMultiline;
begin
  Assert.AreEqual(TStringLiterals.ToLiteral('select *'#10'from Kunde', '    ', False, True,
    TStringLiteralSettings.Default, #10), ToLiteral(StoreWith(cUnitLf), 5, 'select *'#10'from Kunde', True));
  Assert.StartsWith('''''''', ToLiteral(StoreWith(cUnitLf), 5, 'select *'#10'from Kunde', True));
end;

/// <summary>Ohne Position und mit nicht geöffnetem Dokument.</summary>
procedure AssertRejectsMissingPositionOrDocument;
begin
  // Ohne Position.
  Assert.WillRaise(
    procedure
    var
      Args: TJSONArray;
    begin
      Args := TJSONArray.Create;
      try
        Args.Add(TDocumentUris.FromPath(cMainFile));
        TStringLiteralCommands.ExecutePlainText(StoreWith(cUnitLf), Args).Free;
      finally
        Args.Free;
      end;
    end, EJsonRpcError);
  // Dokument nicht geöffnet.
  Assert.WillRaise(
    procedure
    var
      Args: TJSONArray;
      Store: IDocumentStore;
    begin
      // Erst in eine Interface-Variable: Ein Konstruktor direkt am const-Parameter würde nie freigegeben.
      Store := TDocumentStore.Create;
      Args := Arguments(4, 12, '');
      try
        TStringLiteralCommands.ExecutePlainText(Store, Args).Free;
      finally
        Args.Free;
      end;
    end, EJsonRpcError);
end;

/// <summary>textToLiteral ohne Text oder mit einem Objekt statt Text.</summary>
procedure AssertToLiteralRejectsNonText;
begin
  // textToLiteral ohne Text bzw. mit einem Objekt statt Text.
  Assert.WillRaise(
    procedure
    var
      Args: TJSONArray;
    begin
      Args := Arguments(4, 0, '');
      try
        TStringLiteralCommands.ExecuteToLiteral(StoreWith(cUnitLf), TStringLiteralSettings.Default, False,
          Args).Free;
      finally
        Args.Free;
      end;
    end, EJsonRpcError);
  Assert.WillRaise(
    procedure
    var
      Args: TJSONArray;
    begin
      Args := Arguments(4, 0, '');
      try
        Args.AddElement(TJSONObject.Create);
        TStringLiteralCommands.ExecuteToLiteral(StoreWith(cUnitLf), TStringLiteralSettings.Default, False,
          Args).Free;
      finally
        Args.Free;
      end;
    end, EJsonRpcError);
end;

procedure TStringLiteralCommandsTests.RejectsBadArguments;
begin
  AssertRejectsMissingPositionOrDocument;
  AssertToLiteralRejectsNonText;
  // Eine Zahl ist kein Text, obwohl TJSONNumber von TJSONString erbt.
  Assert.WillRaise(
    procedure
    var
      Args: TJSONArray;
    begin
      Args := Arguments(4, 0, '');
      try
        Args.Add(1);
        TStringLiteralCommands.ExecuteToLiteral(StoreWith(cUnitLf), TStringLiteralSettings.Default, False,
          Args).Free;
      finally
        Args.Free;
      end;
    end, EJsonRpcError);
end;

initialization
  TDUnitX.RegisterTestFixture(TStringLiteralCommandsTests);

end.
