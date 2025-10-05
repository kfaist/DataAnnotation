class Annotator:
    def supports(self, task_type: str) -> bool:
        return True

    def annotate(self, sample, context=None):
        # Return a structure understood by adapters, or flags for manual review
        return {"labels": {}, "confidence": 0.0}
