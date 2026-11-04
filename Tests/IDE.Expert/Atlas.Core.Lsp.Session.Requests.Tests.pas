unit Atlas.Core.Lsp.Session.Requests.Tests;

// Vorfahren der LSP-Sitzung allein (Aufteilung von Atlas.Core.Lsp.Session in Json, Base, Requests): Abgleich in
// TLspSessionBase und eine Anfrage in TLspSessionRequests mit einem Client, der feste Antworten gibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspSessionPartsTests = class
  public
    /// <summary>TLspSessionBase: didOpen, didChange nur bei geändertem Text, didClose.</summary>
    [Test]
    procedure BaseClassSyncsDocuments;
    /// <summary>TLspSessionRequests: Referenzen mit Ort; Einträge ohne Datei fallen weg.</summary>
    [Test]
    procedure RequestsClassReadsReferences;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Session.Json,
  Atlas.Core.Lsp.Session.Base,
  Atlas.Core.Lsp.Session.Requests;

/// <summary>Methode und Parameter der gerahmten Nachricht ABytes.</summary>
function MessageOf(const ABytes: TBytes; out AId: Integer; out AParams: string): string;
var
  Text: string;
  Message: TJSONValue;
begin
  Text := TEncoding.UTF8.GetString(ABytes);
  Message := TJSONObject.ParseJSONValue(Text.Substring(Text.IndexOf(#13#10#13#10) + 4));
  try
    Result := Message.GetValue<string>('method', '');
    AId := Message.GetValue<Integer>('id', 0);
    AParams := '';
    if Message.FindValue('params') <> nil then
    begin
      AParams := Message.FindValue('params').ToJSON;
    end;
  finally
    Message.Free;
  end;
end;

/// <summary>Client, der jede Nachricht in ASeen notiert und Anfragen mit AAnswer beantwortet.</summary>
function AnsweringClient(ASeen: TStrings; const AAnswer: string): TLspClient;
var
  Client: TLspClient;
begin
  Client := nil;
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    var
      Id: Integer;
      Params, Method: string;
      Reply: TBytes;
    begin
      Method := MessageOf(ABytes, Id, Params);
      ASeen.Add(Method + ' ' + Params);
      if Id > 0 then
      begin
        Reply := TLspClient.Frame(Format('{"jsonrpc":"2.0","id":%d,"result":%s}', [Id, AAnswer]));
        Client.Receive(Reply, Length(Reply));
      end;
    end);
  Result := Client;
end;

procedure TLspSessionPartsTests.BaseClassSyncsDocuments;
var
  Seen: TStringList;
  Client: TLspClient;
  Session: TLspSessionBase;
  Text: string;
begin
  Seen := TStringList.Create;
  Client := AnsweringClient(Seen, 'null');
  Session := TLspSessionBase.Create(Client);
  try
    Session.Sync('C:\P\A.pas', 'unit A;');
    Session.Sync('C:\P\A.pas', 'unit A;');
    Session.Sync('C:\P\A.pas', 'unit A2;');
    Assert.IsTrue(Session.SyncedText('c:\p\a.pas', Text));
    Assert.AreEqual('unit A2;', Text);
    Session.Close('C:\P\A.pas');
    Assert.AreEqual(3, Seen.Count, 'gleicher Text ohne didChange');
    Assert.StartsWith('textDocument/didOpen ', Seen[0]);
    Assert.StartsWith('textDocument/didChange ', Seen[1]);
    Assert.StartsWith('textDocument/didClose ', Seen[2]);
    Assert.AreEqual(0, Integer(Length(Session.SyncedFiles)));
  finally
    Session.Free;
    Client.Free;
    Seen.Free;
  end;
end;

procedure TLspSessionPartsTests.RequestsClassReadsReferences;
var
  Seen: TStringList;
  Client: TLspClient;
  Session: TLspSessionRequests;
  Locations: TArray<TLspLocation>;
begin
  Seen := TStringList.Create;
  Client := AnsweringClient(Seen, '[{"uri":"file:///c:/p/kunde.pas","range":{"start":{"line":3,"character":4},' +
    '"end":{"line":3,"character":9}}},{"uri":"","range":{"start":{"line":1,"character":0}}}]');
  Session := TLspSessionRequests.Create(Client);
  try
    Locations := Session.References('C:\P\A.pas', 2, 5);
    Assert.AreEqual(1, Integer(Length(Locations)), 'ohne Datei fällt weg');
    Assert.AreEqual(3, Locations[0].Line);
    Assert.AreEqual(4, Locations[0].Character);
    Assert.Contains(Seen.Text, '"includeDeclaration":false');
  finally
    Session.Free;
    Client.Free;
    Seen.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSessionPartsTests);

end.
