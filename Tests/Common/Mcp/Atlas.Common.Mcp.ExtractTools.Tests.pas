unit Atlas.Common.Mcp.ExtractTools.Tests;

// Tests für das MCP-Werkzeug extract_method (#2054): Vorschau mit gleichen Stellen, Schreiben mit Wunschname, ohne
// gleiche Stellen nur die Auswahl, Fehler bei ungültigen Zeilen und nicht extrahierbaren Anweisungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpExtractToolsTests = class
  public
    [Test]
    procedure PreviewNamesEqualPlacesAndWritesNothing;
    [Test]
    procedure WritesWithNameAndOnlySelection;
    [Test]
    procedure RefusesBadLinesNamesAndStatements;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.EditTools,
  Atlas.Common.Mcp.ExtractTools;

const
  cSource = 'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TParser = class'#10 +
    '  private'#10 +
    '    FCount: Integer;'#10 +
    '  public'#10 +
    '    procedure A(AValue: Integer);'#10 +
    '    procedure B(AValue: Integer);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TParser.A(AValue: Integer);'#10 +
    'begin'#10 +
    '  FCount := FCount + AValue;'#10 +
    '  Writeln(FCount);'#10 +
    'end;'#10 +
    'procedure TParser.B(AValue: Integer);'#10 +
    'begin'#10 +
    '  FCount := FCount + AValue;'#10 +
    '  Writeln(FCount);'#10 +
    'end;'#10 +
    'end.'#10;

type
  /// <summary>Eine Datei im Speicher.</summary>
  TMemoryFile = class
  public
    Text: string;
    Writes: Integer;
  end;

function Tools(AFile: TMemoryFile): TMcpEditTools;
begin
  Result := TMcpEditTools.Create(nil,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := AFile.Text;
      Result := AFileName = 'U.pas';
    end,
    procedure(const AFileName, AText: string)
    begin
      AFile.Text := AText;
      Inc(AFile.Writes);
    end,
    function: TArray<string>
    begin
      Result := nil;
    end,
    nil);
end;

function Request(AStartLine, AEndLine: Integer; const AName: string; ADuplicates, ADryRun: Boolean):
  TMcpExtractRequest;
begin
  Result := Default(TMcpExtractRequest);
  Result.FileName := 'U.pas';
  Result.StartLine := AStartLine;
  Result.EndLine := AEndLine;
  Result.Name := AName;
  Result.ReplaceDuplicates := ADuplicates;
  Result.DryRun := ADryRun;
  Result.Style := TFormatStyle.Default;
  Result.InlineVar := True;
end;

{ TMcpExtractToolsTests }

procedure TMcpExtractToolsTests.PreviewNamesEqualPlacesAndWritesNothing;
var
  mFile: TMemoryFile;
  mEdit: TMcpEditTools;
  mReport: string;
begin
  mFile := TMemoryFile.Create;
  mEdit := Tools(mFile);
  try
    mFile.Text := cSource;
    mReport := TMcpExtractTools.ExtractMethod(mEdit, Request(14, 15, 'Count', True, True));
    Assert.Contains(mReport, 'Methode extrahieren und gleiche Stelle ersetzen');
    Assert.Contains(mReport, 'Zeile 19 in TParser.B');
    Assert.Contains(mReport, '+   Count(AValue);');
    Assert.AreEqual(0, mFile.Writes);
    Assert.AreEqual(cSource, mFile.Text);
  finally
    mEdit.Free;
    mFile.Free;
  end;
end;

procedure TMcpExtractToolsTests.WritesWithNameAndOnlySelection;
var
  mFile: TMemoryFile;
  mEdit: TMcpEditTools;
begin
  mFile := TMemoryFile.Create;
  mEdit := Tools(mFile);
  try
    mFile.Text := cSource;
    TMcpExtractTools.ExtractMethod(mEdit, Request(14, 15, 'Count', False, False));
    Assert.AreEqual(1, mFile.Writes);
    Assert.Contains(mFile.Text, 'procedure TParser.Count(const AValue: Integer);');
    // Ohne replaceDuplicates bleibt B unverändert.
    Assert.Contains(mFile.Text, 'procedure TParser.B(AValue: Integer);'#10'begin'#10'  FCount := FCount + AValue;');
    mFile.Text := cSource;
    TMcpExtractTools.ExtractMethod(mEdit, Request(14, 15, '', True, False));
    Assert.Contains(mFile.Text, 'procedure TParser.B(AValue: Integer);'#10'begin'#10'  ExtractedMethod(AValue);');
  finally
    mEdit.Free;
    mFile.Free;
  end;
end;

procedure TMcpExtractToolsTests.RefusesBadLinesNamesAndStatements;
var
  mFile: TMemoryFile;
  mEdit: TMcpEditTools;
begin
  mFile := TMemoryFile.Create;
  mEdit := Tools(mFile);
  try
    mFile.Text := cSource;
    Assert.WillRaise(
      procedure
      begin
        TMcpExtractTools.ExtractMethod(mEdit, Request(15, 14, '', True, True));
      end, EMcpToolError);
    Assert.WillRaise(
      procedure
      begin
        TMcpExtractTools.ExtractMethod(mEdit, Request(14, 15, '1x', True, True));
      end, EMcpToolError);
    // Zeile 12 ist der Kopf der Routine, keine Anweisung.
    Assert.WillRaise(
      procedure
      begin
        TMcpExtractTools.ExtractMethod(mEdit, Request(12, 12, '', True, True));
      end, EMcpToolError);
    Assert.AreEqual(0, mFile.Writes);
  finally
    mEdit.Free;
    mFile.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpExtractToolsTests);

end.
