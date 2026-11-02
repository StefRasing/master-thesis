"""Internal signal for cooperative search cancellation."""
struct SearchTimeout <: Exception end
Base.showerror(io::IO, ::SearchTimeout) = print(io, "Search deadline exceeded")

# Use a monotonic clock so wall-clock adjustments cannot change the budget.
_search_time() = time_ns() / 1.0e9
function _check_deadline(deadline::Real)
    _search_time() >= deadline && throw(SearchTimeout())
    return nothing
end
