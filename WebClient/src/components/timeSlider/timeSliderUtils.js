/**
 * TimeSlider is a UI component for displaying and manipulating a timeline.
 * 
 * TimeSliderUtils is an utility class holding time slider domain utilities.
 */

/* globals d3 */

var TimeSliderUtils = {
    createTimeScale: function (currentTime) {
        var tsStart = new Date(currentTime.getTime() - TimeSliderUtils.DAY);
        var tsEnd = new Date(currentTime.getTime() + TimeSliderUtils.DAY);
        return d3.scaleTime().domain([tsStart, tsEnd]);
    },

    createDate: function (date, timeDeltaMs) {
        return new Date(date.getTime() + timeDeltaMs);
    }
};
Object.defineProperty(TimeSliderUtils, 'SECOND', { value: 1000 });
Object.defineProperty(TimeSliderUtils, 'MINUTE', { value: 60 * TimeSliderUtils.SECOND });
Object.defineProperty(TimeSliderUtils, 'HOUR', { value: 60 * TimeSliderUtils.MINUTE });
Object.defineProperty(TimeSliderUtils, 'DAY', { value: 24 * TimeSliderUtils.HOUR });

export default TimeSliderUtils;
