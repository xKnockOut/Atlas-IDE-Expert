unit Atlas.Common.Lsp.Internals.Feature;

// Gemeinsame Grundlage der LSP-Dienste, die über Dokumentspeicher und
// Symbolindex arbeiten (Definition, Hervorhebung, semantische Token …), und
// derer, die zusätzlich Projektdateien lesen (Referenzen, Hierarchien,
// Datenfluss, Auswirkungen, Code Lens). Die Dienste übernehmen nur die
// Felder; was sie damit tun, bleibt bei ihnen.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract;

type
  /// <summary>Projektdateien, die nach Verweisen durchsucht werden.</summary>
  TLspFilesProvider = reference to function: TArray<string>;

  /// <summary>Dienst mit Dokumentspeicher, Symbolindex und optionalem Nachladen von Units (AEnsureUnit = nil:
  /// nur der Index).</summary>
  TLspIndexFeature = class
  protected
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc);
  end;

  /// <summary>Wie TLspIndexFeature, dazu Lesen nicht geöffneter Dateien und die Projektdateien.</summary>
  TLspProjectFeature = class(TLspIndexFeature)
  protected
    FReadText: TDocumentReadText;
    FFiles: TLspFilesProvider;
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TDocumentReadText;
      const AFiles: TLspFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
  end;

/// <summary>Unit der Datei AFileName: ACurrent (Stand aus dem Editor), wenn sie es ist, sonst aus AIndex.</summary>
function UnitOfFile(const AIndex: ISymbolIndex; const ACurrent: TUnitIndex; const AFileName: string;
  out AUnit: TUnitIndex): Boolean;

implementation

uses
  System.SysUtils;

function UnitOfFile(const AIndex: ISymbolIndex; const ACurrent: TUnitIndex; const AFileName: string;
  out AUnit: TUnitIndex): Boolean;
begin
  if SameText(AFileName, ACurrent.FileName) then
  begin
    AUnit := ACurrent;
    Exit(True);
  end;
  Result := AIndex.FindFile(AFileName, AUnit);
end;

{ TLspIndexFeature }

constructor TLspIndexFeature.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
end;

{ TLspProjectFeature }

constructor TLspProjectFeature.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TDocumentReadText; const AFiles: TLspFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create(AStore, AIndex, AEnsureUnit);
  FReadText := AReadText;
  FFiles := AFiles;
end;

end.
