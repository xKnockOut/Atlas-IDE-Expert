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
  mText: string;
  mMessage: TJSONValue;
begin
  mText := TEncoding.UTF8.GetString(ABytes);
  mMessage := TJSONObject.ParseJSONValue(mText.Substring(mText.IndexOf(#13#10#13#10) + 4));
  try
    Result := mMessage.GetValue<string>('method', '');
    AId := mMessage.GetValue<Integer>('id', 0);
    AParams := '';
    if mMessage.FindValue('params') <> nil then
    begin
      AParams := mMessage.FindValue('params').ToJSON;
    end;
  finally
    mMessage.Free;
  end;
end;

/// <summary>Client, der jede Nachricht in ASeen notiert und Anfragen mit AAnswer beantwortet.</summary>
function AnsweringClient(ASeen: TStrings; const AAnswer: string): TLspClient;
var
  mClient: TLspClient;
begin
  mClient := nil;
  mClient := TLspClient.Create(
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
        mClient.Receive(Reply, Length(Reply));
      end;
    end);
  Result := mClient;
end;

procedure TLspSessionPartsTests.BaseClassSyncsDocuments;
var
  mSeen: TStringList;
  mClient: TLspClient;
  mSession: TLspSessionBase;
  mText: string;
begin
  mSeen := TStringList.Create;
  mClient := AnsweringClient(mSeen, 'null');
  mSession := TLspSessionBase.Create(mClient);
  try
    mSession.Sync('C:\P\A.pas', 'unit A;');
    mSession.Sync('C:\P\A.pas', 'unit A;');
    mSession.Sync('C:\P\A.pas', 'unit A2;');
    Assert.IsTrue(mSession.SyncedText('c:\p\a.pas', mText));
    Assert.AreEqual('unit A2;', mText);
    mSession.Close('C:\P\A.pas');
    Assert.AreEqual(3, mSeen.Count, 'gleicher Text ohne didChange');
    Assert.StartsWith('textDocument/didOpen ', mSeen[0]);
    Assert.StartsWith('textDocument/didChange ', mSeen[1]);
    Assert.StartsWith('textDocument/didClose ', mSeen[2]);
    Assert.AreEqual(0, Integer(Length(mSession.SyncedFiles)));
  finally
    mSession.Free;
    mClient.Free;
    mSeen.Free;
  end;
end;

procedure TLspSessionPartsTests.RequestsClassReadsReferences;
var
  mSeen: TStringList;
  mClient: TLspClient;
  mSession: TLspSessionRequests;
  mLocations: TArray<TLspLocation>;
begin
  mSeen := TStringList.Create;
  mClient := AnsweringClient(mSeen, '[{"uri":"file:///c:/p/kunde.pas","range":{"start":{"line":3,"character":4},' +
    '"end":{"line":3,"character":9}}},{"uri":"","range":{"start":{"line":1,"character":0}}}]');
  mSession := TLspSessionRequests.Create(mClient);
  try
    mLocations := mSession.References('C:\P\A.pas', 2, 5);
    Assert.AreEqual(1, Integer(Length(mLocations)), 'ohne Datei fällt weg');
    Assert.AreEqual(3, mLocations[0].Line);
    Assert.AreEqual(4, mLocations[0].Character);
    Assert.Contains(mSeen.Text, '"includeDeclaration":false');
  finally
    mSession.Free;
    mClient.Free;
    mSeen.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSessionPartsTests);

end.
