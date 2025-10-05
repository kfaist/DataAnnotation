from .base import Annotator

class TextGenericAnnotator(Annotator):
    def annotate(self, sample, context=None):
        # Placeholder logic: pass-through with low confidence; adapters decide to assist/pre-fill only
        return {"labels": {"answer": "placeholder"}, "confidence": 0.2}
