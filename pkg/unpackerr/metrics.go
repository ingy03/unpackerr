package unpackerr

import (
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"golift.io/starr"
	"golift.io/version"
	"golift.io/xtractr"
)

// metrics holds the non-custom Prometheus collector metrics for the app.
type metrics struct {
	AppQueues      *prometheus.GaugeVec
	AppRequests    *prometheus.HistogramVec
	ArchivesRead   *prometheus.CounterVec
	BytesWritten   *prometheus.CounterVec
	ExtractTime    *prometheus.HistogramVec
	FilesExtracted *prometheus.CounterVec
	Uptime         prometheus.CounterFunc
}

// MetricsCollector is used to plug into a custom Prometheus metrics collector.
type MetricsCollector struct {
	*Unpackerr
	counter *prometheus.Desc
	gauge   *prometheus.Desc
	buffer  *prometheus.Desc
}

// Describe satisfies the Prometheus custom metrics collector.
func (c *MetricsCollector) Describe(ch chan<- *prometheus.Desc) {
	for _, desc := range []*prometheus.Desc{c.counter, c.gauge, c.buffer} {
		ch <- desc
	}
}

// Collect satisfies the Prometheus custom metrics collector.
func (c *MetricsCollector) Collect(ch chan<- prometheus.Metric) {
	stats := c.stats()
	ch <- prometheus.MustNewConstMetric(c.gauge, prometheus.GaugeValue, float64(stats.Waiting), "waiting")
	ch <- prometheus.MustNewConstMetric(c.gauge, prometheus.GaugeValue, float64(stats.Queued), "queued")
	ch <- prometheus.MustNewConstMetric(c.gauge, prometheus.GaugeValue, float64(stats.Extracting), "extracting")
	ch <- prometheus.MustNewConstMetric(c.gauge, prometheus.GaugeValue, float64(stats.Failed), "failed")
	ch <- prometheus.MustNewConstMetric(c.gauge, prometheus.GaugeValue, float64(stats.Extracted), "extracted")
	ch <- prometheus.MustNewConstMetric(c.gauge, prometheus.GaugeValue, float64(stats.Imported), "imported")
	ch <- prometheus.MustNewConstMetric(c.gauge, prometheus.GaugeValue, float64(stats.Deleted), "deleted")
	ch <- prometheus.MustNewConstMetric(c.counter, prometheus.CounterValue, float64(stats.HookOK), "hook_ok")
	ch <- prometheus.MustNewConstMetric(c.counter, prometheus.CounterValue, float64(stats.HookFail), "hook_fail")
	ch <- prometheus.MustNewConstMetric(c.counter, prometheus.CounterValue, float64(stats.CmdOK), "cmd_ok")
	ch <- prometheus.MustNewConstMetric(c.counter, prometheus.CounterValue, float64(stats.CmdFail), "cmd_fail")
	ch <- prometheus.MustNewConstMetric(c.counter, prometheus.CounterValue, float64(c.Retries), "retries")
	ch <- prometheus.MustNewConstMetric(c.counter, prometheus.CounterValue, float64(c.Finished), "finished")
	ch <- prometheus.MustNewConstMetric(c.buffer, prometheus.GaugeValue, float64(len(c.folders.Events)), "folder_events")
	ch <- prometheus.MustNewConstMetric(c.buffer, prometheus.GaugeValue, float64(len(c.updates)), "xtractr_updates")
	ch <- prometheus.MustNewConstMetric(c.buffer, prometheus.GaugeValue, float64(len(c.folders.Updates)), "folder_updates")
	ch <- prometheus.MustNewConstMetric(c.buffer, prometheus.GaugeValue, float64(len(c.delChan)), "deletes")
	ch <- prometheus.MustNewConstMetric(c.buffer, prometheus.GaugeValue, float64(len(c.hookChan)), "hooks")
}

// updateMetrics observes metrics for each completed extraction. The url for a folder is the watch path.
func (u *Unpackerr) updateMetrics(resp *xtractr.Response, app starr.App, url string) {
	if u.metrics == nil {
		return
	}

	u.metrics.ArchivesRead.WithLabelValues(string(app), url).Add(float64(mapLen(resp.Archives) + mapLen(resp.Extras)))
	u.metrics.BytesWritten.WithLabelValues(string(app), url).Add(float64(resp.Size))
	u.metrics.ExtractTime.WithLabelValues(string(app), url).Observe(resp.Elapsed.Seconds())
	u.metrics.FilesExtracted.WithLabelValues(string(app), url).Add(float64(len(resp.NewFiles)))
}

// saveQueueMetrics observes metrics for each starr app queue request.
func (u *Unpackerr) saveQueueMetrics(size int, start time.Time, app starr.App, url string) {
	if u.metrics == nil {
		return
	}

	u.metrics.AppQueues.WithLabelValues(string(app), url).Set(float64(size))
	u.metrics.AppRequests.WithLabelValues(string(app), url).Observe(time.Since(start).Seconds())
}

// setupMetrics is called once on startup if metrics are enabled.
func (u *Unpackerr) setupMetrics() {
	prometheus.MustRegister(&MetricsCollector{
		Unpackerr: u,
		counter:   prometheus.NewDesc("unpackerr_counters", "Unpackerr queue counters", []string{"name"}, nil),
		gauge:     prometheus.NewDesc("unpackerr_gauges", "Unpackerr queue gauges", []string{"name"}, nil),
		buffer:    prometheus.NewDesc("unpackerr_buffers", "Unpackerr channel buffer gauges", []string{"name"}, nil),
	})

	u.metrics = &metrics{
		AppQueues: promauto.NewGaugeVec(prometheus.GaugeOpts{
			Name: "unpackerr_app_queue_size",
			Help: "The total number of items queued in a Starr app",
		}, []string{"app", "url"}),
		AppRequests: promauto.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "unpackerr_app_queue_fetch_time_seconds",
			Help:    "The duration of queue fetch API requests to Starr apps",
			Buckets: []float64{0.005, 0.025, .1, .5, 1, 3, 10},
		}, []string{"app", "url"}),
		ArchivesRead: promauto.NewCounterVec(prometheus.CounterOpts{
			Name: "unpackerr_archives_read_total",
			Help: "The total number of archive files read",
		}, []string{"app", "url"}),
		BytesWritten: promauto.NewCounterVec(prometheus.CounterOpts{
			Name: "unpackerr_bytes_written_total",
			Help: "The total number bytes written to disk",
		}, []string{"app", "url"}),
		ExtractTime: promauto.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "unpackerr_extract_time_seconds",
			Help:    "The duration of extractions",
			Buckets: []float64{10, 60, 300, 1800, 3600, 7200, 14400},
		}, []string{"app", "url"}),
		FilesExtracted: promauto.NewCounterVec(prometheus.CounterOpts{
			Name: "unpackerr_files_extracted_total",
			Help: "The total number files written to disk",
		}, []string{"app", "url"}),
		Uptime: promauto.NewCounterFunc(prometheus.CounterOpts{
			Name: "unpackerr_uptime_seconds_total",
			Help: "Duration Unpackerr has been running in seconds",
		}, func() float64 { return time.Since(version.Started).Seconds() }),
	}
}

// Stats is filled and returned when a stats request is issued.
type Stats struct {
	Waiting    uint
	Queued     uint
	Extracting uint
	Failed     uint
	Extracted  uint
	Imported   uint
	Deleted    uint
	HookOK     uint
	HookFail   uint
	CmdOK      uint
	CmdFail    uint
}

// stats compiles and builds the statistics for the app.
func (u *Unpackerr) stats() *Stats {
	stats := &Stats{}
	stats.HookOK, stats.HookFail = u.WebhookCounts()
	stats.CmdOK, stats.CmdFail = u.CmdhookCounts()

	for name := range u.Map {
		switch u.Map[name].Status {
		case WAITING:
			stats.Waiting++
		case QUEUED:
			stats.Queued++
		case EXTRACTING:
			stats.Extracting++
		case DELETEFAILED, EXTRACTFAILED:
			stats.Failed++
		case EXTRACTED:
			stats.Extracted++
		case DELETED, DELETING:
			stats.Deleted++
		case IMPORTED:
			stats.Imported++
		}
	}

	return stats
}
