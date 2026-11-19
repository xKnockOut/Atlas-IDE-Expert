unit Atlas.UI.Signature.Adapters.HintView;

// Der Parameter-Hint (TAtlasSignatureHint) als Ansicht des Controllers (IAtlasSignatureView aus
// Atlas.Core.Signature.Contract). Reicht nur weiter; der Controller hält den Adapter, die Kompositionswurzel
// setzt ihn über TAtlasSignatureViews.Factory ein.

interface

uses
  Atlas.Core.Signature.Contract,
  Atlas.Core.Signature.Controller,
  Atlas.UI.Signature.Hint;

type
  TAtlasSignatureHintView = class(TInterfacedObject, IAtlasSignatureView)
  private
    FHint: TAtlasSignatureHint;
  public
    /// <summary>AHint lebt so lange wie die Nutzer des Adapters (Controller).</summary>
    constructor Create(AHint: TAtlasSignatureHint);
    procedure ShowSignature(const AHelp: TAtlasSignatureHelp; ASignature, AParameter: Integer);
    procedure HideSignature;
  end;

implementation

{ TAtlasSignatureHintView }

constructor TAtlasSignatureHintView.Create(AHint: TAtlasSignatureHint);
begin
  inherited Create;
  FHint := AHint;
end;

procedure TAtlasSignatureHintView.ShowSignature(const AHelp: TAtlasSignatureHelp; ASignature, AParameter: Integer);
begin
  FHint.ShowSignature(AHelp, ASignature, AParameter);
end;

procedure TAtlasSignatureHintView.HideSignature;
begin
  FHint.HideSignature;
end;

end.
