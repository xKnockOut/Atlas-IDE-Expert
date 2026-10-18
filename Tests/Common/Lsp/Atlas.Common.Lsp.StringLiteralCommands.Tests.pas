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
  MainFile = 'C:\P\Haupt.pas';
  UnitLf =
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
  Result.Open(TDocumentUris.FromPath(MainFile), 'delphi', 1, AText);
end;

/// <summary>Argumente URI, Position und, wenn AText nicht leer ist, der Text.</summary>
function Arguments(ALine, ACharacter: Integer; const AText: string): TJSONArray;
var
  Position: TJSONObject;
begin
  Result := TJSONArray.Create;
  Result.Add(TDocumentUris.FromPath(MainFile));
  Position := TJSONObject.Create;
  Position.AddPair('line', TJSONNumber.Create(ALine));
  Position.AddPair('character', TJSONNumber.Create(ACharacter));
  Result.AddElement(Position);
  if AText <> '' then
    Result.Add(AText);
end;

function ToLiteral(const AStore: IDocumentStore; ALine: Integer; const AText: string; AMultiline: Boolean): string;
var
  Args: TJSONArray;
  Answer: TJSONValue;
  Settings: TStringLiteralSettings;
begin
  Settings := TStringLiteralSettings.Default;
  Settings.LineBreak := TStringLiteralBreak.SLineBreak;
  Settings.MaxLineLength := 0;
  Args := Arguments(ALine, 0, AText);
  try
    Answer := TStringLiteralCommands.ExecuteToLiteral(AStore, Settings, AMultiline, Args);
    try
      Result := Answer.Value;
    finally
      Answer.Free;
    end;
  finally
    Args.Free;
  end;
end;

{ TStringLiteralCommandsTests }

procedure TStringLiteralCommandsTests.PlainTextOfConcatenatedLiteral;
var
  Args: TJSONArray;
  Answer: TJSONValue;
begin
  Args := Arguments(4, 12, '');
  try
    Answer := TStringLiteralCommands.ExecutePlainText(StoreWith(UnitLf), Args);
    try
      Assert.IsTrue(Answer is TJSONString);
      Assert.AreEqual('select *'#13#10'from Kunde', Answer.Value);
    finally
      Answer.Free;
    end;
  finally
    Args.Free;
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
        TStringLiteralCommands.ExecutePlainText(StoreWith(UnitLf), Args).Free;
      finally
        Args.Free;
      end;
    end, EJsonRpcError);
end;

procedure TStringLiteralCommandsTests.ToLiteralUsesIndentOfLine;
begin
  Assert.AreEqual('''select *'' + sLineBreak +'#10'    ''from Kunde''',
    ToLiteral(StoreWith(UnitLf), 5, 'select *'#10'from Kunde', False));
  // Zeile ohne Einzug.
  Assert.AreEqual('''a'' + sLineBreak +'#10'''b''', ToLiteral(StoreWith(UnitLf), 0, 'a'#10'b', False));
end;

procedure TStringLiteralCommandsTests.ToLiteralUsesLineBreakOfDocument;
begin
  Assert.AreEqual('''select *'' + sLineBreak +'#13#10'    ''from Kunde''',
    ToLiteral(StoreWith(StringReplace(UnitLf, #10, #13#10, [rfReplaceAll])), 5, 'select *'#10'from Kunde', False));
end;

procedure TStringLiteralCommandsTests.ToLiteralMultiline;
begin
  Assert.AreEqual(TStringLiterals.ToLiteral('select *'#10'from Kunde', '    ', False, True,
    TStringLiteralBreak.SLineBreak, 0, #10), ToLiteral(StoreWith(UnitLf), 5, 'select *'#10'from Kunde', True));
  Assert.StartsWith('''''''', ToLiteral(StoreWith(UnitLf), 5, 'select *'#10'from Kunde', True));
end;

procedure TStringLiteralCommandsTests.RejectsBadArguments;
begin
  // Ohne Position.
  Assert.WillRaise(
    procedure
    var
      Args: TJSONArray;
    begin
      Args := TJSONArray.Create;
      try
        Args.Add(TDocumentUris.FromPath(MainFile));
        TStringLiteralCommands.ExecutePlainText(StoreWith(UnitLf), Args).Free;
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
  // textToLiteral ohne Text bzw. mit einem Objekt statt Text.
  Assert.WillRaise(
    procedure
    var
      Args: TJSONArray;
    begin
      Args := Arguments(4, 0, '');
      try
        TStringLiteralCommands.ExecuteToLiteral(StoreWith(UnitLf), TStringLiteralSettings.Default, False,
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
        TStringLiteralCommands.ExecuteToLiteral(StoreWith(UnitLf), TStringLiteralSettings.Default, False,
          Args).Free;
      finally
        Args.Free;
      end;
    end, EJsonRpcError);
  // Eine Zahl ist kein Text, obwohl TJSONNumber von TJSONString erbt.
  Assert.WillRaise(
    procedure
    var
      Args: TJSONArray;
    begin
      Args := Arguments(4, 0, '');
      try
        Args.Add(1);
        TStringLiteralCommands.ExecuteToLiteral(StoreWith(UnitLf), TStringLiteralSettings.Default, False,
          Args).Free;
      finally
        Args.Free;
      end;
    end, EJsonRpcError);
end;

initialization
  TDUnitX.RegisterTestFixture(TStringLiteralCommandsTests);

end.
